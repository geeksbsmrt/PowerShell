---
trigger: glob
globs: "**/*.{ps1,psm1,psd1,ps1xml,pssc,psrc,cdxml}"
---

# PowerShell Engineering Standards & Style Guide

## 1. Technical Environment

- **Runtime**: PowerShell 7.0+
- **Platform**: Cross-platform (macOS/Windows/Linux).
- **Integration**: .NET 10 (C# 14). Use explicit type accelerators (e.g., `[string]`, `[int]`) and fully qualified .NET namespaces where ambiguity exists.

## 2. PoshCode Style Guide Integration

Follow the principles in [PowerShell Practice and Style](https://github.com/PoshCode/PowerShellPracticeAndStyle):

### Naming Conventions

- **PascalCase**: Use for all public identifiers: module names, function/cmdlet names, classes, enums, attributes, public fields, properties, and parameters.
- **lowercase**: Use for language keywords (`foreach`, `if`, `try`) and operators (`-eq`, `-match`).
- **UPPERCASE**: Use for Comment-Based Help (CBH) keywords (`.SYNOPSIS`, `.DESCRIPTION`).
- **Full Names**: Avoid aliases (e.g., use `Get-ChildItem` instead of `gci` or `ls`). Use full parameter names (e.g., `-Path` instead of `-p`).
- **Verb-Noun**: Adhere to standard PowerShell `Verb-Noun` pairs.

### Code Layout & Formatting

- **One True Brace Style (OTBS)**:
  - Opening brace on the same line as the statement.
  - Closing brace on its own line.
- **Indentation**: Exactly 4 spaces per level.
- **Line Length**: Limit to 115 characters. Use **Splatting** for commands with many parameters. Use implied line continuation inside brackets/braces over backticks.
- **Whitespace**:
  - Surround function/class definitions with **two blank lines**.
  - Single space around operators (`=`, `+`, `-eq`) and after commas/semicolons.
  - Single space *inside* subexpressions `$( ... )` and scriptblocks `{ ... }` to distinguish from variable delimiters.

### String Handling

- **Variable Delimiters**: Variables in expandable strings MUST use variable delimiter braces `${variable}` unless used in a true subexpression `$(...)`.
  - **Correct**: `"Hello, ${Name}"`, `"Path: ${PSScriptRoot}/Data"`, `"Value: $( $Object.Property )"`
  - **Incorrect**: `"Hello, $Name"`, `"Path: $PSScriptRoot/Data"`

## 3. Function Structure & Documentation

- **Mandatory CmdletBinding**: Every function must start with `[CmdletBinding()]` and `param()`.
- **Order of Execution**: Follow the explicit block order: `begin {}`, `process {}`, `end {}`.
- **Comment-Based Help (CBH)**: Every function must include:
  - `.SYNOPSIS`: Brief description.
  - `.PARAMETER`: Description of each parameter.
  - `.EXAMPLE`: Working usage example.
  - `.NOTES`: Complexity or side-effect descriptions.

## 4. Error Handling & Reliability

- **Terminating Errors**: Use `-ErrorAction Stop` on cmdlets to ensure `try/catch` catches all errors.
- **Catch Blocks**:
  - Immediately copy `$PSItem` (or `$_`) to a specific variable to avoid hijacking.
  - Include `$PSItem.Exception.Message` and `$PSItem.InvocationInfo.PositionMessage` in logs.
- **Idempotency**: Verify resource existence (`Test-Path`, `Get-Module -ListAvailable`) before modification.
- **Full Paths**: Avoid relative paths (`.` or `..`) or `~`. Use `$PSScriptRoot` or `${Env:UserProfile}`.

## 5. Pester 5 Testing Standards

- **File Naming**: Unit tests must reside in `*.Tests.ps1` files.
- **Discovery/Run Lifestyle**:
  - Use `BeforeAll` for setup and `AfterAll` for cleanup.
  - Wrap tests in `Describe` and `Context` blocks.
  - Use `It` for individual test assertions.
- **Mocking**: Use `Mock` for external dependencies (APIs, FileSystem, Registry) to ensure isolation and speed.
- **Assertions**: Use the `-Should` operator (e.g., `$Result | Should -Be $Expected`).

## 6. .NET 10 Integration

- **High Performance**: Use `[System.Text.Json.JsonSerializer]` for JSON.
- **Generic Collections**: Use `[System.Collections.Generic.List[PSObject]]` instead of fixed-size arrays where dynamic growth is needed.
