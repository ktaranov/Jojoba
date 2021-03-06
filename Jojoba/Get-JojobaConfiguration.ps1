<#

.SYNOPSIS
Extract -Jojoba parameters passed to the function calling Jojoba.

.DESCRIPTION
Jojoba doesn't accept parameters directly, instead any parameters passed to
the calling function with a -Jojoba prefix are picked up.

.PARAMETER Caller
The top-level $PSCmdlet variable as it exists in Jojoba, before this function
is called.

.EXAMPLE
$configuration = Get-JojobaConfiguration $PSCmdlet

.NOTES
This is for internal use by Jojoba and should not be called externally.

#>

function Get-JojobaConfiguration {
    [CmdletBinding()]
    [OutputType("System.Collections.Hashtable")]
    param (
        $Caller
    )

    begin {
    }

    process {
        $callerModule = $Caller.GetVariableValue("MyInvocation").MyCommand.ModuleName
        $callerFunction = $Caller.GetVariableValue("MyInvocation").MyCommand.Name
        if ($callerFunction) {
            $callerCommand = $Caller.GetVariableValue("MyInvocation").MyCommand
            if (!$callerCommand) {
                Write-Error "No caller command"
            }

            $argumentName = $null
            $inputName = $null
            foreach ($key in $callerCommand.Parameters.Keys.GetEnumerator()) {
                if ($callerCommand.Parameters[$key].ParameterSets.ContainsKey($Caller.ParameterSetName) -and
                    (
                        $callerCommand.Parameters[$key].ParameterSets[$Caller.ParameterSetName].ValueFromPipeline -or
                        $callerCommand.Parameters[$key].ParameterSets[$Caller.ParameterSetName].ValueFromPipelineByPropertyName
                    ) -and
                    (
                        $callerCommand.Parameters[$key].Name -eq "InputObject" -or
                        $callerCommand.Parameters[$key].Aliases -contains "InputObject"
                    )) {
                    $inputName = $Key
                }

                if ($callerCommand.Parameters[$key].ParameterSets.ContainsKey($Caller.ParameterSetName) -and
                    $callerCommand.Parameters[$key].ParameterSets[$Caller.ParameterSetName].ValueFromRemainingArguments) {
                    $argumentName = $Key
                }
            }

            # Get the ValueFromRemainingArguments
            if (!$argumentName) {
                Write-Error "Jojoba requires a parameter with ValueFromRemainingArguments"
            }
            if (!$inputName) {
                Write-Error "Jojoba requires a parameter variable aliased to InputObject"
            }

            # Maybe no -Jojoba arguments were specified, and that's okay!
            if (!($arguments = $Caller.GetVariableValue($argumentName))) {
                $arguments = @()
            }
        } else {
            Write-Error "Jojoba can only be used from within functions"
        }

        # If this is the first run, generate and store the batch number
        if ($arguments -notcontains "-JojobaBatch") {
            $arguments += "-JojobaBatch", [guid]::NewGuid().ToString()
            $Caller.SessionState.PSVariable.Set($argumentName, $arguments)
        }

        $settings = @{
            # Internal use
            Module       = $callerModule
            Function     = $callerFunction
            ArgumentName = $argumentName
            InputName    = $inputName
            Unsafe       = $false

            # Automatic populations
            Suite        = $callerModule
            ClassName    = $callerFunction
            Name         = $Caller.GetVariableValue($inputName)

            # Manual switches
            Quiet        = $false
            PassThru     = $false
            Throttle     = $env:NUMBER_OF_PROCESSORS
            Jenkins      = if ($env:JENKINS_SERVER_COOKIE) {
                ".\Jojoba.xml"
            } else {
                $false
            }
        }

        for ($i = 0; $arguments -and $i -lt $arguments.Count; $i++) {
            if ($arguments[$i] -and $arguments[$i] -match '^-Jojoba(.*?)(?::?)$') {
                if (($i + 1) -eq $arguments.Count -or $arguments[$i + 1] -like "-*") {
                    $settings[$Matches[1]] = $true
                } else {
                    $settings[$Matches[1]] = $arguments[++$i]
                }
            }
        }

        # Resolve full path
        if ($settings.Jenkins) {
            $settings.Jenkins = Join-Path (Resolve-Path (Split-Path $settings.Jenkins)) (Split-Path $settings.Jenkins -Leaf)
        }

        $settings
    }

    end {
    }
}
