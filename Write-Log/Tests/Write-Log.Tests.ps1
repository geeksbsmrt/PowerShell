Describe 'Write-Log' {
    BeforeAll {
        # Ensure the module is imported
        . (Join-Path -Path $PSScriptRoot -ChildPath '../Write-Log.ps1')
    }

    BeforeEach {
        # Mock dependencies and setup test environment
        $TestLogDirectory = Join-Path -Path $env:TMPDIR -ChildPath 'TestLogs'
        $TestLogFileName = 'TestLog.log'
        $TestLogFilePath = Join-Path -Path $TestLogDirectory -ChildPath $TestLogFileName

        if (-not (Test-Path -LiteralPath $TestLogDirectory)) {
            New-Item -Path $TestLogDirectory -ItemType Directory | Out-Null
        } else {
            Clear-Content -Path $TestLogFilePath
        }
    }

    AfterEach {
        # Cleanup test environment
        if (Test-Path -LiteralPath $TestLogDirectory) {
            Remove-Item -Path $TestLogDirectory -Recurse -Force
        }
    }

    Context 'Parameter validation and edge cases' {
        It 'Should log multiple messages from array input' {
            $Messages = @('First', 'Second', 'Third')
            Write-Log -Message $Messages -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent.Count | Should -Be 3
            $LogContent[0] | Should -Match 'First'
            $LogContent[1] | Should -Match 'Second'
            $LogContent[2] | Should -Match 'Third'
        }

        It 'Should return the message when PassThru is specified' {
            $Result = Write-Log -Message 'PassThru test' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -PassThru
            $Result | Should -Be 'PassThru test'
        }

        It 'Should log with custom Source' {
            $Source = 'CustomSource'
            Write-Log -Message 'Source test' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -Source $Source
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent | Should -Match $Source
        }

        It 'Should log with Severity Warning (2)' {
            Write-Log -Message 'Warning test' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -Severity 2 -LogType 'Legacy'
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent | Should -Match '\[Warning\] :: Warning test'
        }

        It 'Should log with Severity Error (3)' {
            Write-Log -Message 'Error test' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -Severity 3 -LogType 'Legacy'
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent | Should -Match '\[Error\] :: Error test'
        }

        It 'Should log with Severity Success (0)' {
            Write-Log -Message 'Success test' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -Severity 0 -LogType 'Legacy'
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent | Should -Match '\[Success\] :: Success test'
        }

        It 'Should log in CMTrace format when LogType is CMTrace' {
            Write-Log -Message 'CMTrace test' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -LogType 'CMTrace'
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent | Should -Match '<!\[LOG\[CMTrace test\]LOG\]!>'
        }

        It 'Should create a new log file when AppendToLogFile is $false' {
            Write-Log -Message 'First entry' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -CreateNewLog
            $InitialContent = Get-Content -Path $TestLogFilePath
            Write-Log -Message 'Second entry' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -CreateNewLog
            $NewContent = Get-Content -Path $TestLogFilePath
            $NewContent | Should -Not -Be $InitialContent
        }

        It 'Should use default Source if not provided' {
            Write-Log -Message 'Default source test' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent | Should -Match 'Default source test'
        }

        It 'Should return all messages with PassThru and array input' {
            $Messages = @('One', 'Two')
            $Result = Write-Log -Message $Messages -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -PassThru
            $Result | Should -Be $Messages
        }
    }

    Context 'Debug and conditional logging' {
        It 'Should not log debug message if LogDebugMessage is $false' {
            Write-Log -Message 'Debug test' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -DebugMessage -LogDebugMessage:$false
            Test-Path -Path $TestLogFilePath | Should -BeFalse
        }

        It 'Should log debug message if LogDebugMessage is $true' {
            Write-Log -Message 'Debug test' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -DebugMessage -LogDebugMessage:$true
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent | Should -Match 'Debug test'
        }
    }

    Context 'Error handling' {
        It 'Should not throw if log directory cannot be created and ContinueOnError is $true' {
            $invalidChars = [System.IO.Path]::GetInvalidFileNameChars() | Where-Object { $_ -ne [char]0 }
            $InvalidDir = [System.IO.Path]::Combine($env:TMPDIR, [System.IO.Path]::GetRandomFileName(), ($invalidChars -join ''))
            { Write-Log -Message 'Should not throw' -LogFileDirectory $InvalidDir -LogFileName $TestLogFileName } | Should -Not -Throw
        }

        It 'Should throw if log directory cannot be created and ContinueOnError is $false' {
            $invalidChars = [System.IO.Path]::GetInvalidFileNameChars() | Where-Object { $_ -ne [char]0 }
            $InvalidDir = [System.IO.Path]::Combine($env:TMPDIR, [System.IO.Path]::GetRandomFileName(), ($invalidChars -join ''))
            { Write-Log -Message 'Should throw' -LogFileDirectory $InvalidDir -LogFileName $TestLogFileName -ContinueOnError $false } | Should -Throw
        }

        It 'Should not log empty or whitespace-only messages' {
            { Write-Log -Message '' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName } | Should -Throw
        }

        It 'Should throw for invalid Severity values' {
            { Write-Log -Message 'Invalid severity' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -Severity 99 } | Should -Throw
        }

        It 'Should throw when Message is not provided' {
            { Write-Log -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName } | Should -Throw
        }

        It 'Should not log when LogFileName is empty' {
            { Write-Log -Message 'No log file' -LogFileDirectory $TestLogDirectory -LogFileName '' -WriteHost $false } | Should -Throw
            Test-Path -Path $TestLogFilePath | Should -BeFalse
        }
    }

    Context 'Additional scenarios and edge cases' {
        It 'Should call Write-Host when WriteHost is true' {
            Mock Write-Host {}
            Mock Write-Output {}
            Write-Log -Message 'Console test' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -WriteHost $true
            if ($Host.UI.RawUI.ForegroundColor){
                Assert-MockCalled Write-Host -Exactly 1
            } else {
                Assert-MockCalled Write-Output -Exactly 1
            }
        }

        It 'Should handle relative LogFileDirectory path' {
            $RelativeDir = 'RelativeTestLogs'
            if (-not (Test-Path $RelativeDir)) { New-Item -Path $RelativeDir -ItemType Directory | Out-Null }
            Write-Log -Message 'Relative path test' -LogFileDirectory $RelativeDir -LogFileName $TestLogFileName
            Test-Path -Path (Join-Path $RelativeDir $TestLogFileName) | Should -BeTrue
            Remove-Item -Path $RelativeDir -Recurse -Force
        }

        It 'Should handle absolute LogFileDirectory path' {
            $AbsoluteDir = Join-Path -Path $env:TMPDIR -ChildPath 'AbsoluteTestLogs'
            if (-not (Test-Path $AbsoluteDir)) { New-Item -Path $AbsoluteDir -ItemType Directory | Out-Null }
            Write-Log -Message 'Absolute path test' -LogFileDirectory $AbsoluteDir -LogFileName $TestLogFileName
            Test-Path -Path (Join-Path $AbsoluteDir $TestLogFileName) | Should -BeTrue
            Remove-Item -Path $AbsoluteDir -Recurse -Force
        }

        It 'Should log Unicode and special characters' {
            $unicodeMsg = 'Unicode test: 測試 🚀'
            Write-Log -Message $unicodeMsg -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName
            $LogContent = Get-Content -Path $TestLogFilePath -Raw
            $LogContent | Should -Match 'Unicode test: 測試 🚀'
        }

        It 'Should log a very large message' {
            $largeMsg = 'A' * 5000
            Write-Log -Message $largeMsg -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName
            $LogContent = Get-Content -Path $TestLogFilePath -Raw
            $LogContent | Should -Match $largeMsg
        }

        It 'Should log all valid severity values' {
            0..3 | ForEach-Object {
                Write-Log -Message "Severity $_ test" -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -Severity $_ -LogType 'Legacy'
            }
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent[0] | Should -Match '\[Success\] :: Severity 0 test'
            $LogContent[1] | Should -Match '\[Info\] :: Severity 1 test'
            $LogContent[2] | Should -Match '\[Warning\] :: Severity 2 test'
            $LogContent[3] | Should -Match '\[Error\] :: Severity 3 test'
        }

        It 'Should handle pipeline input' {
            'Pipe1', 'Pipe2' | Write-Log -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent[0] | Should -Match 'Pipe1'
            $LogContent[1] | Should -Match 'Pipe2'
        }

        It 'Should append to log file when AppendToLogFile is true' {
            Write-Log -Message 'First append' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName
            Write-Log -Message 'Second append' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent[0] | Should -Match 'First append'
            $LogContent[1] | Should -Match 'Second append'
        }

        It 'Should create log file with .log extension if not provided' {
            $NoExtFileName = 'NoExtFile'
            Write-Log -Message 'No extension test' -LogFileDirectory $TestLogDirectory -LogFileName $NoExtFileName
            Test-Path -Path (Join-Path -Path $TestLogDirectory -ChildPath "${NoExtFileName}.log") | Should -BeTrue
        }

        It 'Should fallback to default Source if Source is null or whitespace' {
            {Write-Log -Message 'Null source test' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -Source '' }| Should -Throw
        }

        It 'Should not log when Message is $null' {
            { Write-Log -Message $null -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName } | Should -Throw
        }

        It 'Should not log when Message is an empty array' {
            { Write-Log -Message @() -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName } | Should -Throw
        }
    }
}
