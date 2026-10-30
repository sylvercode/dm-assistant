Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultPathValidation.psm1')

# Canonical vault-root resolution (only after the exact-vault authorization
# gate) and component-aware target containment (contract section 5). Every
# path component is examined with .NET filesystem APIs that do not follow
# links; symbolic links and junctions are resolved one hop at a time so an
# escaping or cyclic chain is refused before the target is accessed. No
# external shell command runs, no directory is created, and no replacement
# target is inferred.

$script:DmMaxLinkHops = 40
$script:DmSeparator = [System.IO.Path]::DirectorySeparatorChar

if ($null -eq ('DmAssistant.IO.DirectoryLease' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace DmAssistant.IO
{
    public sealed class UnsafePathException : IOException
    {
        public UnsafePathException() : base("The opened target is a reparse point.") { }
    }

    public sealed class FileSnapshot
    {
        public byte[] Bytes { get; private set; }
        public string FinalPath { get; private set; }

        public FileSnapshot(byte[] bytes, string finalPath)
        {
            Bytes = bytes;
            FinalPath = finalPath;
        }
    }

    public sealed class DirectoryLease : IDisposable
    {
        private const uint FileReadData = 0x1;
        private const uint FileReadAttributes = 0x80;
        private const uint Delete = 0x00010000;
        private const uint ShareRead = 0x1;
        private const uint ShareWrite = 0x2;
        private const uint OpenExisting = 3;
        private const uint CreateNew = 1;
        private const uint GenericWrite = 0x40000000;
        private const uint FileAttributeTemporary = 0x00000100;
        private const uint BackupSemantics = 0x02000000;
        private const uint OpenReparsePoint = 0x00200000;
        private const uint SequentialScan = 0x08000000;
        private const uint FileAttributeReparsePoint = 0x00000400;
        private const int FileAttributeTagInfo = 9;
        private static readonly object LeaseSync = new object();
        private static readonly Dictionary<string, LeaseEntry> ActiveLeases =
            new Dictionary<string, LeaseEntry>(StringComparer.OrdinalIgnoreCase);
        private readonly List<string> leaseKeys = new List<string>();

        private sealed class LeaseEntry
        {
            public SafeFileHandle Handle;
            public int References;

            public LeaseEntry(SafeFileHandle handle)
            {
                Handle = handle;
                References = 1;
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SecurityAttributes
        {
            public int Length;
            public IntPtr SecurityDescriptor;
            [MarshalAs(UnmanagedType.Bool)]
            public bool InheritHandle;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FileAttributeTagInformation
        {
            public uint FileAttributes;
            public uint ReparseTag;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(
            string path, uint access, uint share, IntPtr securityAttributes,
            uint creationDisposition, uint flags, IntPtr template);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(
            string path, uint access, uint share, ref SecurityAttributes securityAttributes,
            uint creationDisposition, uint flags, IntPtr template);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandleEx(
            SafeFileHandle handle, int informationClass, out FileAttributeTagInformation information, uint size);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandle(
            SafeFileHandle handle, StringBuilder path, uint length, uint flags);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(
            string descriptor, uint revision, out IntPtr securityDescriptor, out uint size);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LocalFree(IntPtr memory);

        private static string ToExtendedPath(string path)
        {
            var fullPath = Path.GetFullPath(path);
            if (fullPath.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase))
                return fullPath;
            if (fullPath.StartsWith(@"\\", StringComparison.Ordinal))
                return @"\\?\UNC\" + fullPath.Substring(2);
            return @"\\?\" + fullPath;
        }

        public static SafeFileHandle CreateProtectedStage(string path)
        {
            IntPtr descriptor;
            uint size;
            if (!ConvertStringSecurityDescriptorToSecurityDescriptor(
                "D:P(A;;FA;;;OW)", 1, out descriptor, out size))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "A restricted staging descriptor could not be created.");

            try
            {
                var attributes = new SecurityAttributes
                {
                    Length = Marshal.SizeOf(typeof(SecurityAttributes)),
                    SecurityDescriptor = descriptor,
                    InheritHandle = false
                };
                var handle = CreateFile(ToExtendedPath(path), GenericWrite, 0, ref attributes,
                    CreateNew, FileAttributeTemporary, IntPtr.Zero);
                if (handle.IsInvalid)
                {
                    var error = Marshal.GetLastWin32Error();
                    handle.Dispose();
                    throw new Win32Exception(error, "A protected staging file could not be created.");
                }
                return handle;
            }
            finally
            {
                LocalFree(descriptor);
            }
        }

        public static DirectoryLease Acquire(string[] paths)
        {
            var lease = new DirectoryLease();
            try
            {
                lock (LeaseSync)
                {
                    foreach (var path in paths)
                    {
                        var key = Path.GetFullPath(path);
                        var pathRoot = Path.GetPathRoot(key);
                        if (key.Length > pathRoot.Length)
                            key = key.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

                        LeaseEntry existing;
                        if (ActiveLeases.TryGetValue(key, out existing))
                        {
                            existing.References++;
                            lease.leaseKeys.Add(key);
                            continue;
                        }

                        var handle = CreateFile(ToExtendedPath(path), FileReadAttributes | Delete, ShareRead | ShareWrite,
                            IntPtr.Zero, OpenExisting, BackupSemantics, IntPtr.Zero);
                        if (handle.IsInvalid)
                        {
                            var error = Marshal.GetLastWin32Error();
                            handle.Dispose();
                            throw new Win32Exception(error, "A vault directory could not be leased.");
                        }
                        ActiveLeases.Add(key, new LeaseEntry(handle));
                        lease.leaseKeys.Add(key);
                    }
                }
                return lease;
            }
            catch
            {
                lease.Dispose();
                throw;
            }
        }

        private static string NormalizeHandlePath(string path)
        {
            var resolvedPath = path;
            if (resolvedPath.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase))
                resolvedPath = @"\\" + resolvedPath.Substring(8);
            else if (resolvedPath.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase))
                resolvedPath = resolvedPath.Substring(4);
            return Path.GetFullPath(resolvedPath);
        }

        private static bool IsWithinRoot(string root, string path)
        {
            var normalizedRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (String.Equals(normalizedRoot, path, StringComparison.OrdinalIgnoreCase))
                return true;
            return path.StartsWith(normalizedRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
        }

        public static FileSnapshot ReadFileSnapshot(string path, string canonicalRoot, string expectedPath)
        {
            if (!OperatingSystem.IsWindows())
                throw new PlatformNotSupportedException("Handle-protected vault reads are supported only on Windows.");

            var handle = CreateFile(ToExtendedPath(path), FileReadData | FileReadAttributes, ShareRead,
                IntPtr.Zero, OpenExisting, OpenReparsePoint | SequentialScan, IntPtr.Zero);
            if (handle.IsInvalid)
            {
                var error = Marshal.GetLastWin32Error();
                handle.Dispose();
                throw new Win32Exception(error, "The vault target could not be opened safely.");
            }

            using (handle)
            {
                FileAttributeTagInformation information;
                if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfo,
                    out information, (uint)Marshal.SizeOf(typeof(FileAttributeTagInformation))))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "The opened target could not be verified.");
                if ((information.FileAttributes & FileAttributeReparsePoint) != 0)
                    throw new UnsafePathException();

                var capacity = 512;
                var finalPath = new StringBuilder(capacity);
                uint length;
                while ((length = GetFinalPathNameByHandle(handle, finalPath, (uint)capacity, 0)) >= capacity)
                {
                    capacity = checked((int)length + 1);
                    finalPath = new StringBuilder(capacity);
                }
                if (length == 0)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "The opened target path could not be verified.");

                var resolvedPath = NormalizeHandlePath(finalPath.ToString());
                var normalizedExpectedPath = Path.GetFullPath(expectedPath);
                if (!IsWithinRoot(canonicalRoot, resolvedPath) ||
                    !String.Equals(resolvedPath, normalizedExpectedPath, StringComparison.OrdinalIgnoreCase))
                    throw new UnsafePathException();

                using (var stream = new FileStream(handle, FileAccess.Read, 4096, false))
                using (var bytes = new MemoryStream())
                {
                    stream.CopyTo(bytes);
                    return new FileSnapshot(bytes.ToArray(), resolvedPath);
                }
            }
        }

        public void Dispose()
        {
            lock (LeaseSync)
            {
                for (var index = leaseKeys.Count - 1; index >= 0; index--)
                {
                    LeaseEntry entry;
                    if (!ActiveLeases.TryGetValue(leaseKeys[index], out entry))
                        continue;
                    entry.References--;
                    if (entry.References == 0)
                    {
                        entry.Handle.Dispose();
                        ActiveLeases.Remove(leaseKeys[index]);
                    }
                }
                leaseKeys.Clear();
            }
        }
    }
}
'@ -ErrorAction Stop
}

function Get-DmPathComparison {
    <#
    .SYNOPSIS
    Returns the operating-system-specific comparison used for vault paths.
    #>
    if ($IsLinux) { return [System.StringComparison]::Ordinal }
    [System.StringComparison]::OrdinalIgnoreCase
}

function ConvertTo-DmNativeSeparator {
    <#
    .SYNOPSIS
    Converts slash separators to native separators on Windows.
    .PARAMETER Path
    Path string whose separators should be normalized.
    #>
    param([string]$Path)
    if ($IsWindows) { return $Path.Replace('/', '\') }
    $Path
}

function Split-DmPathComponent {
    <#
    .SYNOPSIS
    Splits a path into nonempty native path components.
    .PARAMETER Path
    Path string to split.
    #>
    param([string]$Path)
    [char[]]$separators = if ($IsWindows) { '\', '/' } else { '/' }
    [string[]]$Path.Split($separators, [System.StringSplitOptions]::RemoveEmptyEntries)
}

function Get-DmExceptionKind {
    <#
    .SYNOPSIS
    Classifies a filesystem error as missing or inaccessible.
    .PARAMETER ErrorRecord
    PowerShell error record whose exception chain is inspected.
    #>
    param($ErrorRecord)
    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        if ($exception -is [System.IO.FileNotFoundException] -or $exception -is [System.IO.DirectoryNotFoundException]) { return 'missing' }
        if ($exception -is [System.UnauthorizedAccessException] -or $exception -is [System.IO.IOException] -or $exception -is [System.Security.SecurityException]) { return 'inaccessible' }
        $exception = $exception.InnerException
    }
    'inaccessible'
}

function Get-DmFileSystemEntry {
    <#
    .SYNOPSIS
    Reads one filesystem entry's attributes without following its link target.
    .DESCRIPTION
    Returns an exists, missing, or inaccessible state and any link target.
    .PARAMETER Path
    Absolute filesystem entry path to examine.
    #>
    param([Parameter(Mandatory)][string]$Path)
    try { $attributes = [System.IO.File]::GetAttributes($Path) }
    catch { return [pscustomobject]@{ state = (Get-DmExceptionKind -ErrorRecord $_); isDirectory = $false; linkTarget = $null } }
    $isDirectory = ($attributes -band [System.IO.FileAttributes]::Directory) -ne 0
    $linkTarget = $null
    if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        try {
            $info = if ($isDirectory) { [System.IO.DirectoryInfo]::new($Path) } else { [System.IO.FileInfo]::new($Path) }
            # A reparse point that is not a symbolic link or junction (for example a cloud placeholder) has no link target.
            $linkTarget = $info.LinkTarget
        }
        catch { return [pscustomobject]@{ state = 'inaccessible'; isDirectory = $isDirectory; linkTarget = $null } }
    }
    [pscustomobject]@{ state = 'exists'; isDirectory = $isDirectory; linkTarget = $linkTarget }
}

function ConvertFrom-DmLinkTarget {
    <#
    .SYNOPSIS
    Classifies a link target as absolute, relative, or unresolvable.
    .PARAMETER Target
    Raw link target; supported Windows namespace prefixes are normalized.
    #>
    param([string]$Target)
    $t = ConvertTo-DmNativeSeparator -Path $Target
    if ($IsWindows) {
        if ($t.StartsWith('\??\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) { $t = '\\' + $t.Substring(8) }
        elseif ($t.StartsWith('\\?\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) { $t = '\\' + $t.Substring(8) }
        elseif ($t.StartsWith('\??\') -or $t.StartsWith('\\?\')) { $t = $t.Substring(4) }
        if ($t.StartsWith('\\.\') -or $t.StartsWith('\??\') -or $t.StartsWith('\\?\')) { return [pscustomobject]@{ kind = 'unresolvable'; path = $null } }
    }
    if ([string]::IsNullOrWhiteSpace($t)) { return [pscustomobject]@{ kind = 'unresolvable'; path = $null } }
    if ([System.IO.Path]::IsPathFullyQualified($t)) { return [pscustomobject]@{ kind = 'absolute'; path = $t } }
    if ([System.IO.Path]::IsPathRooted($t)) { return [pscustomobject]@{ kind = 'unresolvable'; path = $null } }
    [pscustomobject]@{ kind = 'relative'; path = $t }
}

function Test-DmPathWithinRoot {
    <#
    .SYNOPSIS
    Tests textual containment on path-component boundaries.
    .DESCRIPTION
    Component-aware containment: $true when Path equals Root or lies beneath
    it on a component boundary. Comparison defaults to OrdinalIgnoreCase on
    Windows and macOS and Ordinal on Linux. Both paths must already be
    absolute and free of '.' and '..' components; this is purely textual.
    .PARAMETER Root
    Canonical absolute root path.
    .PARAMETER Path
    Absolute candidate path to compare with the root.
    .PARAMETER Comparison
    String comparison to use; defaults to the platform's path comparison.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [System.StringComparison]$Comparison = (Get-DmPathComparison)
    )
    $r = ConvertTo-DmNativeSeparator -Path $Root
    $p = ConvertTo-DmNativeSeparator -Path $Path
    $rootOfRoot = [System.IO.Path]::GetPathRoot($r)
    if ($r.Length -gt $rootOfRoot.Length) { $r = $r.TrimEnd($script:DmSeparator) }
    $pathRoot = [System.IO.Path]::GetPathRoot($p)
    if ($p.Length -gt $pathRoot.Length) { $p = $p.TrimEnd($script:DmSeparator) }
    if ([string]::Equals($r, $p, $Comparison)) { return $true }
    $prefix = if ($r.EndsWith($script:DmSeparator)) { $r } else { $r + $script:DmSeparator }
    $p.StartsWith($prefix, $Comparison)
}

function Open-DmVaultDirectoryLease {
    <#
    .SYNOPSIS
    Holds the verified vault directory chain against rename or replacement.
    .DESCRIPTION
    Opens the canonical vault root and each target-parent directory with
    delete access and without delete sharing, preventing replacement while
    the verified target is read or written. Nested operations share each
    existing directory handle rather than weakening its lease.
    .PARAMETER Boundary
    Authorized canonical vault boundary containing the target.
    .PARAMETER Resolution
    Previously resolved target whose parent directory chain is held.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)]$Resolution
    )
    if (-not $IsWindows) { throw [System.PlatformNotSupportedException]::new('Safe directory leases are supported only on Windows.') }
    $root = [System.IO.Path]::GetFullPath([string]$Boundary.canonicalRoot)
    $parent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetDirectoryName([string]$Resolution.resolvedPath))
    if (-not (Test-DmPathWithinRoot -Root $root -Path $parent -Comparison $Boundary.comparison)) {
        throw [System.UnauthorizedAccessException]::new('The target directory is outside the authorized vault.')
    }
    $paths = [System.Collections.Generic.List[string]]::new()
    $paths.Add($root)
    $relative = [System.IO.Path]::GetRelativePath($root, $parent)
    if ($relative -cne '.') {
        $current = $root
        foreach ($component in ($relative -split '[\\/]')) {
            if ([string]::IsNullOrEmpty($component) -or $component -ceq '.' -or $component -ceq '..') {
                throw [System.UnauthorizedAccessException]::new('The target directory chain is not contained by the vault.')
            }
            $current = [System.IO.Path]::Combine($current, $component)
            $paths.Add($current)
        }
    }
    [DmAssistant.IO.DirectoryLease]::Acquire($paths.ToArray())
}

function Read-DmVaultFileHandleSnapshot {
    <#
    .SYNOPSIS
    Reads a file through a handle opened without following a leaf reparse point.
    .PARAMETER Path
    Previously resolved absolute target path.
    .PARAMETER Root
    Canonical absolute vault root used to verify the opened handle before reading.
    .PARAMETER ExpectedPath
    Previously resolved absolute target path that the opened handle must match.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ExpectedPath
    )
    [DmAssistant.IO.DirectoryLease]::ReadFileSnapshot($Path, $Root, $ExpectedPath)
}

function Resolve-DmCanonicalDirectory {
    <#
    .SYNOPSIS
    Resolves an absolute directory component by component.
    .DESCRIPTION
    Follows symbolic links and junctions. Returns @{ status; path } where
    status is ok, invalid, missing, notDirectory, inaccessible, or cycle.
    .PARAMETER Path
    Explicit absolute directory path to resolve.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $fail = { param([string]$Status) [pscustomobject]@{ status = $Status; path = $null } }
    $normalized = ConvertTo-DmNativeSeparator -Path $Path
    if (-not [System.IO.Path]::IsPathFullyQualified($normalized)) { return (& $fail 'invalid') }
    $root = [System.IO.Path]::GetPathRoot($normalized)
    $components = Split-DmPathComponent -Path $normalized.Substring($root.Length)
    if (@($components | Where-Object { $_ -ceq '.' -or $_ -ceq '..' }).Count -gt 0) { return (& $fail 'invalid') }

    $queue = [System.Collections.Generic.List[string]]::new()
    $queue.AddRange([string[]]$components)
    $current = $root
    $hops = 0
    while ($queue.Count -gt 0) {
        $component = $queue[0]
        $queue.RemoveAt(0)
        if ($component -ceq '.') { continue }
        if ($component -ceq '..') {
            $parent = [System.IO.Path]::GetDirectoryName($current)
            if (-not [string]::IsNullOrEmpty($parent)) { $current = $parent }
            continue
        }
        $candidate = [System.IO.Path]::Join($current, $component)
        $entry = Get-DmFileSystemEntry -Path $candidate
        if ($entry.state -cne 'exists') { return (& $fail $entry.state) }
        if ($null -ne $entry.linkTarget) {
            $hops++
            if ($hops -gt $script:DmMaxLinkHops) { return (& $fail 'cycle') }
            $target = ConvertFrom-DmLinkTarget -Target $entry.linkTarget
            switch ($target.kind) {
                'absolute' {
                    $targetRoot = [System.IO.Path]::GetPathRoot($target.path)
                    $queue.InsertRange(0, [string[]](Split-DmPathComponent -Path $target.path.Substring($targetRoot.Length)))
                    $current = $targetRoot
                }
                'relative' { $queue.InsertRange(0, [string[]](Split-DmPathComponent -Path $target.path)) }
                default { return (& $fail 'cycle') }
            }
            continue
        }
        if (-not $entry.isDirectory) { return (& $fail 'notDirectory') }
        $current = $candidate
    }
    $final = Get-DmFileSystemEntry -Path $current
    if ($final.state -cne 'exists') { return (& $fail $final.state) }
    if (-not $final.isDirectory) { return (& $fail 'notDirectory') }
    if ($current.Length -gt $root.Length) { $current = $current.TrimEnd($script:DmSeparator) }
    [pscustomobject]@{ status = 'ok'; path = $current }
}

function Resolve-DmVaultRoot {
    <#
    .SYNOPSIS
    Resolves an authorized explicit vault root to a canonical boundary.
    .DESCRIPTION
    Resolves the explicit vault root to its canonical directory. Runs only
    after the exact-vault authorization gate: -Gate must be the passed
    'vault-authorization' gate outcome for the same request, otherwise this
    throws. Returns [pscustomobject]@{ gate = 'vault-root'; passed; result;
    evidence; boundary } where boundary is @{ selectedRoot; canonicalRoot;
    comparison } when passed, else $null and result is a VAULT_TARGET_INVALID
    contract result. The root path is never echoed in results.
    .PARAMETER Gate
    Passed exact-vault authorization gate outcome for the request.
    .PARAMETER VaultRoot
    Explicit absolute vault-root directory to resolve.
    .PARAMETER Operation
    Operation identifier included if root resolution fails.
    .PARAMETER Targets
    Requested vault-relative targets reported as not attempted on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Gate,
        [Parameter(Mandatory)][AllowEmptyString()][string]$VaultRoot,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operation,
        [AllowEmptyCollection()][string[]]$Targets = @()
    )
    $gateName = 'vault-root'
    if ($null -eq $Gate -or -not $Gate.PSObject.Properties['gate'] -or $Gate.gate -cne 'vault-authorization' -or -not $Gate.passed) {
        throw [System.InvalidOperationException]::new('The vault root is resolved only after the exact-vault authorization gate passes.')
    }
    $resolution = Resolve-DmCanonicalDirectory -Path $VaultRoot
    $evidence = @(New-DmEvidence -Gate $gateName -Subject 'vaultRoot' -State $(if ($resolution.status -ceq 'ok') { 'resolved' } else { $resolution.status }))
    if ($resolution.status -cne 'ok') {
        $message = switch ($resolution.status) {
            'missing' { 'The selected vault root does not exist.' }
            'notDirectory' { 'The selected vault root is not a directory.' }
            'inaccessible' { 'The selected vault root or one of its parent folders is inaccessible.' }
            'cycle' { 'The selected vault root has a cyclic or unresolvable link chain.' }
            default { 'The selected vault root is not a valid explicit absolute directory path.' }
        }
        $result = New-DmBlockedResult -Operation $Operation -CompletionCode 'VAULT_TARGET_INVALID' -Targets $Targets -Message $message `
            -RemainingWork @('Select an existing, accessible vault folder explicitly, then retry.') -Detail ([ordered]@{ reason = $resolution.status })
        return [pscustomobject][ordered]@{ gate = $gateName; passed = $false; result = $result; evidence = $evidence; boundary = $null }
    }
    $boundary = [pscustomobject][ordered]@{
        selectedRoot  = $VaultRoot
        canonicalRoot = $resolution.path
        comparison    = (Get-DmPathComparison)
    }
    [pscustomobject][ordered]@{ gate = $gateName; passed = $true; result = $null; evidence = $evidence; boundary = $boundary }
}

function New-DmTargetResolution {
    <#
    .SYNOPSIS
    Constructs a target-resolution record and maps its status to a result code.
    .PARAMETER Path
    Original vault-relative target path.
    .PARAMETER Status
    Resolution state, including resolved, missing, invalid, outside, or inaccessible.
    .PARAMETER ItemType
    Resolved item type: file, directory, or missing.
    .PARAMETER ResolvedPath
    Internal absolute resolved path; do not expose it in contract results.
    .PARAMETER ResolvedRelativePath
    Resolved path relative to the vault boundary.
    .PARAMETER ViaLink
    Whether resolution followed a symbolic link or junction.
    .PARAMETER Reason
    Safe explanation of the resolution outcome.
    #>
    param([string]$Path, [string]$Status, [string]$ItemType = 'missing', [string]$ResolvedPath = $null, [string]$ResolvedRelativePath = $null, [bool]$ViaLink = $false, [string]$Reason = '')
    $code = switch ($Status) {
        'invalid' { 'PATH_INVALID' }
        'outside' { 'PATH_OUTSIDE_VAULT' }
        'inaccessible' { 'READ_FAILED' }
        default { $null }
    }
    [pscustomobject][ordered]@{
        path                 = $Path
        status               = $Status
        code                 = $code
        exists               = ($Status -ceq 'resolved')
        itemType             = $ItemType
        resolvedPath         = $(if ([string]::IsNullOrEmpty($ResolvedPath)) { $null } else { $ResolvedPath })
        resolvedRelativePath = $(if ([string]::IsNullOrEmpty($ResolvedRelativePath)) { $null } else { $ResolvedRelativePath })
        viaLink              = $ViaLink
        reason               = $Reason
    }
}

function Resolve-DmVaultTarget {
    <#
    .SYNOPSIS
    Resolves a vault-relative target while enforcing canonical containment.
    .DESCRIPTION
    Resolves one vault-relative target inside the boundary from
    Resolve-DmVaultRoot. Each component is examined without following links;
    a link hop is followed only while the walk stays inside the canonical
    root, so nothing outside the vault is touched. Returns
    [pscustomobject]@{ path; status; code; exists; itemType; resolvedPath;
    resolvedRelativePath; viaLink; reason } with status resolved (exists),
    missing (code $null), invalid (PATH_INVALID), outside (PATH_OUTSIDE_VAULT:
    escape, cycle, or unprovable containment), or inaccessible (READ_FAILED).
    itemType is file, directory, or missing. resolvedPath is an internal
    absolute path that must never be placed in a contract result.
    .PARAMETER Boundary
    Canonical vault boundary obtained after successful authorization.
    .PARAMETER Path
    Literal slash-separated vault-relative target path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path
    )
    $lexical = Test-DmVaultRelativePath -Path $Path
    if (-not $lexical.isValid) { return (New-DmTargetResolution -Path $Path -Status 'invalid' -Reason $lexical.reason) }
    $root = [string]$Boundary.canonicalRoot
    $comparison = [System.StringComparison]$Boundary.comparison

    $queue = [System.Collections.Generic.List[string]]::new()
    $queue.AddRange([string[]]$lexical.components)
    $stack = [System.Collections.Generic.List[string]]::new()
    $current = $root
    $hops = 0
    $viaLink = $false
    $isDirectory = $true
    $outside = { param([string]$Reason) New-DmTargetResolution -Path $Path -Status 'outside' -ViaLink $viaLink -Reason $Reason }

    while ($queue.Count -gt 0) {
        $component = $queue[0]
        $queue.RemoveAt(0)
        if ($component -ceq '.') { continue }
        if ($component -ceq '..') {
            if ($stack.Count -eq 0) { return (& $outside 'A link resolves above the vault root.') }
            $stack.RemoveAt($stack.Count - 1)
            $current = [System.IO.Path]::GetDirectoryName($current)
            $isDirectory = $true
            continue
        }
        $candidate = [System.IO.Path]::Join($current, $component)
        $entry = Get-DmFileSystemEntry -Path $candidate
        if ($entry.state -ceq 'inaccessible') {
            return (New-DmTargetResolution -Path $Path -Status 'inaccessible' -ViaLink $viaLink -Reason 'A path component is inaccessible.')
        }
        $last = $queue.Count -eq 0
        if ($entry.state -ceq 'missing' -or (-not $entry.isDirectory -and $null -eq $entry.linkTarget -and -not $last)) {
            if (@($queue | Where-Object { $_ -ceq '..' -or $_ -ceq '.' }).Count -gt 0) {
                return (& $outside 'Containment of the remaining link path cannot be proven.')
            }
            $relative = @($stack) + @($component) + @($queue)
            $resolved = [System.IO.Path]::Join($root, ($relative -join $script:DmSeparator))
            return (New-DmTargetResolution -Path $Path -Status 'missing' -ResolvedPath $resolved -ResolvedRelativePath ($relative -join '/') -ViaLink $viaLink -Reason 'The target does not exist.')
        }
        if ($null -ne $entry.linkTarget) {
            $viaLink = $true
            $hops++
            if ($hops -gt $script:DmMaxLinkHops) { return (& $outside 'The link chain is cyclic or too long to prove containment.') }
            $target = ConvertFrom-DmLinkTarget -Target $entry.linkTarget
            switch ($target.kind) {
                'absolute' {
                    if (-not (Test-DmPathWithinRoot -Root $root -Path $target.path -Comparison $comparison)) {
                        return (& $outside 'A link resolves outside the vault.')
                    }
                    $rootLength = $root.TrimEnd($script:DmSeparator).Length
                    $rest = if ($target.path.Length -gt $rootLength) { $target.path.Substring($rootLength) } else { '' }
                    $parts = Split-DmPathComponent -Path $rest
                    if (@($parts | Where-Object { $_ -ceq '.' -or $_ -ceq '..' }).Count -gt 0) {
                        return (& $outside 'Containment of an absolute link target cannot be proven.')
                    }
                    $stack.Clear()
                    $current = $root
                    $queue.InsertRange(0, [string[]]$parts)
                }
                'relative' { $queue.InsertRange(0, [string[]](Split-DmPathComponent -Path $target.path)) }
                default { return (& $outside 'A link target cannot be resolved.') }
            }
            continue
        }
        $stack.Add($component)
        $current = $candidate
        $isDirectory = $entry.isDirectory
    }
    if ($stack.Count -eq 0) {
        return (& $outside 'The target resolves to the vault root itself.')
    }
    New-DmTargetResolution -Path $Path -Status 'resolved' -ItemType $(if ($isDirectory) { 'directory' } else { 'file' }) `
        -ResolvedPath $current -ResolvedRelativePath (@($stack) -join '/') -ViaLink $viaLink -Reason ''
}

function Confirm-DmVaultTarget {
    <#
    .SYNOPSIS
    Rechecks a vault boundary and target immediately before access.
    .DESCRIPTION
    Rechecks the boundary immediately before an access: re-resolves the root
    and the target and compares them with the earlier resolution. Returns
    [pscustomobject]@{ confirmed; code; reason; resolution } where code is
    $null when confirmed, PATH_OUTSIDE_VAULT when the root moved or the
    target now escapes, READ_FAILED when a component became inaccessible,
    and TARGET_CONFLICT when the target now resolves elsewhere or changed
    existence or type.
    .PARAMETER Boundary
    Previously established canonical vault boundary.
    .PARAMETER Resolution
    Earlier target-resolution record to compare with the current target.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)]$Resolution
    )
    $comparison = [System.StringComparison]$Boundary.comparison
    $deny = { param([string]$Code, [string]$Reason, $Fresh) [pscustomobject][ordered]@{ confirmed = $false; code = $Code; reason = $Reason; resolution = $Fresh } }
    $root = Resolve-DmCanonicalDirectory -Path ([string]$Boundary.selectedRoot)
    if ($root.status -cne 'ok' -or -not [string]::Equals($root.path, [string]$Boundary.canonicalRoot, $comparison)) {
        return (& $deny 'PATH_OUTSIDE_VAULT' 'The vault root no longer resolves to the same canonical folder.' $null)
    }
    $fresh = Resolve-DmVaultTarget -Boundary $Boundary -Path ([string]$Resolution.path)
    if ($null -ne $fresh.code) { return (& $deny $fresh.code $fresh.reason $fresh) }
    $sameStatus = $fresh.status -ceq $Resolution.status -and $fresh.itemType -ceq $Resolution.itemType
    $samePath = [string]::Equals([string]$fresh.resolvedPath, [string]$Resolution.resolvedPath, $comparison)
    if (-not ($sameStatus -and $samePath)) {
        return (& $deny 'TARGET_CONFLICT' 'The target changed after it was resolved.' $fresh)
    }
    [pscustomobject][ordered]@{ confirmed = $true; code = $null; reason = ''; resolution = $fresh }
}

function Test-DmUniqueResolvedTargets {
    <#
    .SYNOPSIS
    Detects target aliases that resolve to the same vault path.
    .PARAMETER Boundary
    Canonical vault boundary supplying the platform path comparer.
    .PARAMETER Resolutions
    Resolved target records to compare before target access.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)][object[]]$Resolutions
    )
    $comparer = if ([System.StringComparison]$Boundary.comparison -eq [System.StringComparison]::OrdinalIgnoreCase) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new($comparer)
    foreach ($resolution in $Resolutions) {
        $resolvedPath = [string]$resolution.resolvedPath
        if ([string]::IsNullOrEmpty($resolvedPath)) { continue }
        if (-not $seen.Add($resolvedPath)) {
            return [pscustomobject][ordered]@{
                isUnique      = $false
                duplicatePath = [string]$resolution.path
            }
        }
    }
    [pscustomobject][ordered]@{ isUnique = $true; duplicatePath = $null }
}

function Read-DmVaultTargetBytes {
    <#
    .SYNOPSIS
    Rechecks containment and reads a resolved file's exact bytes.
    .DESCRIPTION
    Confirms the boundary, leases the directory chain, rechecks it, and reads
    from a handle that does not follow a leaf reparse point. The opened
    handle's final path must match the resolved in-vault target. Returns
    [pscustomobject]@{ ok; code; reason; bytes; version } where version is
    'sha256:<hex>' of the bytes read.
    .PARAMETER Boundary
    Canonical vault boundary used for the immediate recheck.
    .PARAMETER Resolution
    Previously resolved file target to confirm and read.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)]$Resolution
    )
    $fail = { param([string]$Code, [string]$Reason) [pscustomobject][ordered]@{ ok = $false; code = $Code; reason = $Reason; bytes = $null; version = $null } }
    $directoryLease = $null
    try {
        $check = Confirm-DmVaultTarget -Boundary $Boundary -Resolution $Resolution
        if (-not $check.confirmed) { return (& $fail $check.code $check.reason) }
        if ($check.resolution.itemType -cne 'file') { return (& $fail 'READ_FAILED' 'The target is not a file.') }
        $directoryLease = Open-DmVaultDirectoryLease -Boundary $Boundary -Resolution $check.resolution
        $lockedCheck = Confirm-DmVaultTarget -Boundary $Boundary -Resolution $check.resolution
        if (-not $lockedCheck.confirmed) { return (& $fail $lockedCheck.code $lockedCheck.reason) }

        $snapshot = Read-DmVaultFileHandleSnapshot `
            -Path ([string]$lockedCheck.resolution.resolvedPath) `
            -Root ([string]$Boundary.canonicalRoot) `
            -ExpectedPath ([string]$lockedCheck.resolution.resolvedPath)
        $expectedPath = [System.IO.Path]::GetFullPath([string]$lockedCheck.resolution.resolvedPath)
        $openedPath = [System.IO.Path]::GetFullPath([string]$snapshot.FinalPath)
        if (-not (Test-DmPathWithinRoot -Root ([string]$Boundary.canonicalRoot) -Path $openedPath -Comparison $Boundary.comparison) -or
            -not [string]::Equals($openedPath, $expectedPath, [System.StringComparison]$Boundary.comparison)) {
            return (& $fail 'PATH_OUTSIDE_VAULT' 'The opened target does not match the verified vault path.')
        }
        $bytes = [byte[]]$snapshot.Bytes
        $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
        [pscustomobject][ordered]@{ ok = $true; code = $null; reason = ''; bytes = $bytes; version = ('sha256:' + [System.Convert]::ToHexString($hash).ToLowerInvariant()) }
    }
    catch [DmAssistant.IO.UnsafePathException] {
        & $fail 'PATH_OUTSIDE_VAULT' 'The target became a reparse point before it was opened.'
    }
    catch {
        & $fail 'READ_FAILED' 'The target could not be read safely.'
    }
    finally {
        if ($null -ne $directoryLease) { $directoryLease.Dispose() }
    }
}

Export-ModuleMember -Function Resolve-DmVaultRoot, Resolve-DmVaultTarget, Confirm-DmVaultTarget, Read-DmVaultTargetBytes, Test-DmPathWithinRoot, Open-DmVaultDirectoryLease, Test-DmUniqueResolvedTargets
