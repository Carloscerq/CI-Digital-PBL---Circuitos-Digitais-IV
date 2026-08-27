$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$zeroWord = '0' * 18

$conversions = @(
    @{
        Input  = 'coefficients/fir/stage1_decim4_q117.hex'
        Output = 'coefficients/fir/stage1_decim4_q117.bin'
        Depth  = 64
    },
    @{
        Input  = 'coefficients/fir/stage2_decim4_q117.hex'
        Output = 'coefficients/fir/stage2_decim4_q117.bin'
        Depth  = 128
    },
    @{
        Input  = 'coefficients/fir/stage3_decim2_q117.hex'
        Output = 'coefficients/fir/stage3_decim2_q117.bin'
        Depth  = 128
    },
    @{
        Input  = 'coefficients/windowing/hann_64_q117.hex'
        Output = 'coefficients/windowing/hann_64_q117.bin'
        Depth  = 64
    }
)

foreach ($conversion in $conversions) {
    $inputPath = Join-Path $projectRoot $conversion.Input
    $outputPath = Join-Path $projectRoot $conversion.Output
    $words = [System.Collections.Generic.List[string]]::new()

    foreach ($rawLine in Get-Content -Path $inputPath) {
        $line = $rawLine.Trim()
        if ($line -eq '') {
            continue
        }
        if ($line -notmatch '^[0-9A-Fa-f]+$') {
            throw "Valor hexadecimal invalido em ${inputPath}: $line"
        }

        $value = [Convert]::ToInt32($line, 16)
        if ($value -gt 0x3FFFF) {
            throw "Valor acima de 18 bits em ${inputPath}: $line"
        }

        $words.Add([Convert]::ToString($value, 2).PadLeft(18, '0'))
    }

    if ($words.Count -gt $conversion.Depth) {
        throw "${inputPath} contem mais palavras que a profundidade configurada."
    }

    while ($words.Count -lt $conversion.Depth) {
        $words.Add($zeroWord)
    }

    [System.IO.File]::WriteAllLines(
        $outputPath,
        $words,
        [System.Text.ASCIIEncoding]::new()
    )
    Write-Host "Gerado: $outputPath ($($words.Count) palavras)"
}
