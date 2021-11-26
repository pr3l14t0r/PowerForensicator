# PowerForensicator 

A module to automate differntial analysis with VMs. 

It has been developed in the course of my master thesis.

More Documentation, use cases etc. to come!

The subdirectory `./HelperScripts` stores scripts that are used for application specific tasks.

## Installation

At the moment this module is neither published in the PSGallery nor available as a NuGet package, but this is on the roadmap. Until then you have to perform a good old manual installation

### Linux (Ubuntu)

- Clone the repository
- Copy the folder `PowerForensicator` to the respective configured paths in your `PSModulePath` environment variable.

```powershell
# Copy module to all paths
$env:PSModulePath.Split(":") | % { Copy-Item "PowerForensicator" -Destination $_ -Recurse -Force -Verbose }

# Import module and test
Import-Module PowerForensicator

Get-Command -Module PowerForensicator
```

### Windows
- Clone the repository
- Copy the folder `PowerForensicator` to the respective configured paths in your `PSModulePath` environment variable.

```powershell
# Copy module to all paths
$env:PSModulePath.Split(";") | % { Copy-Item "PowerForensicator" -Destination $_ -Recurse -Force -Verbose }

# Import module and test
Import-Module PowerForensicator

Get-Command -Module PowerForensicator
```

## Usage
- requires `Vbox4PowerShell`

## File System diffentiator

- fiwalk + idifference2 is used 
- framework iself uses docker for that
- you can also use `fiwalk` **and** `idifference2.py` locally. Please be aware that you need to check the prerequesites yourself for that! The script will only check if everything is there. Both `fiwalk` and `idifference2.py` must be found through your `PATH` variable! 
- EASIEST way is to just use docker (which is default)
- runs faster on ubuntu than windows

Roadmap & Todos: 

- [ ] Resolve `#todo:` comments across the scripts/ cmdlets.
- [ ] Implement DFXML python as a git submodule
- [ ] Create a template for analysis reports 
- [ ] Add functionality for differential analysis of memory dumps
  - [ ] Implement automated usage of volatility or rekall
- [ ] Streamline `Invoke-ActionStateFileExport`
  - [ ] use functions `New-FiwalkXML` and `Invoke-Idifference`
  - [ ] refactor `$RAWFileName` in `Invoke-ActionStateFileExport` to `$ACTIONRawFile`
- `Format-ActionEvidence`
  - [ ] Add second parameterset with `filepath`to directly address idiff files 
- [ ] Add a script named something like `Invoke-Windows10ForensicPreparation` which performs actions on a fresh Windows 10 VM in order to prepare it for forensic investigations.
  - Install the Sysinternal tools on it and add them to path 
  - Disable Windows Defender 
  - List goes on.. 
- [ ] Exchange hardcoded 300seconds timeout in `Wait-PodDeployment` for a parameter like `$TimeOut`