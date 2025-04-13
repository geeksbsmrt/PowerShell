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

    Context 'When writing a log entry' {
        It 'Should create a log file if it does not exist' {
            # Arrange
            Remove-Item -Path $TestLogFilePath -Force -ErrorAction SilentlyContinue

            # Act
            Write-Log -Message 'Test log entry' -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName

            # Assert
            Test-Path -Path $TestLogFilePath | Should -BeTrue
        }

        It 'Should append a log entry to the log file' {
            # Arrange
            $InitialMessage = 'Initial log entry'
            Write-Log -Message $InitialMessage -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName
            $NewMessage = 'New log entry'

            # Act
            Write-Log -Message $NewMessage -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName

            # Assert
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent[0] | Should -Match $InitialMessage
            $LogContent[1] | Should -Match $NewMessage
        }

        It 'Should write a CMTrace-compatible log entry when LogType is CMTrace' {
            # Arrange
            $Message = 'CMTrace log entry'

            # Act
            Write-Log -Message $Message -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -LogType 'CMTrace'

            # Assert
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent | Should -Match "<!\[LOG\[$Message\]LOG\]!>"
        }

        It 'Should write a Legacy log entry when LogType is Legacy' {
            # Arrange
            $Message = 'Legacy log entry'

            # Act
            Write-Log -Message $Message -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -LogType 'Legacy'

            # Assert
            $LogContent = Get-Content -Path $TestLogFilePath
            $LogContent | Should -Match '\[.*\] \[.*\] :: Legacy log entry'
        }
    }

    Context 'When handling log rotation' {
        It 'Should rotate the log file when MaxLogFileSizeMB is exceeded' {
            # Arrange
            $LargeMessage = 'A' * 1024 * 1024 # 1 MB message
            Write-Log -Message $LargeMessage -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -MaxLogFileSizeMB 0.5

            # Act
            Write-Log -Message $LargeMessage -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -MaxLogFileSizeMB 0.5

            # Assert
            $RotatedFiles = Get-ChildItem -Path $TestLogDirectory -Filter '*.log' | Where-Object { $_.Name -ne $TestLogFileName }
            $RotatedFiles.Count | Should -BeGreaterThan 0
        }

        It 'Should retain only the maximum number of log files specified by MaxLogHistory' {
            # Arrange
            $Message = 'Test log entry'
            for ($i = 0; $i -lt 10; $i++) {
                Write-Log -Message $Message -LogFileDirectory $TestLogDirectory -LogFileName $TestLogFileName -MaxLogFileSizeMB 0.1 -MaxLogHistory 3
            }

            # Act
            $LogFiles = Get-ChildItem -Path $TestLogDirectory -Filter '*.log'

            # Assert
            $LogFiles.Count | Should -BeLessOrEqual 3
        }
    }

    Context 'When handling console output' {
        It 'Should write the log entry to the console when WriteHost is $true' {
            # Arrange
            $Message = 'Console log entry'

            # Act
            { Write-Log -Message $Message -WriteHost $true } | Should -Not -Throw
        }

        It 'Should not write the log entry to the console when WriteHost is $false' {
            # Arrange
            $Message = 'Silent log entry'

            # Act
            { Write-Log -Message $Message -WriteHost $false } | Should -Not -Throw
        }
    }
}
