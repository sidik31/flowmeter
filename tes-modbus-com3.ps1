param(
    [string]$Port = 'COM3',
    [int]$SlaveId = 1,
    [string]$Function = '03',
    [int]$Register = 0,
    [int]$Count = 2
)

$ErrorActionPreference = 'Stop'
$BaudRate = 9600
$Factor = 1.0
$Label = 'DEBIT'
$Unit = 'm3/jam'
$ByteOrder = 'DCBA'
$InvariantCulture = [Globalization.CultureInfo]::InvariantCulture

function Get-ModbusCrc {
    param([byte[]]$Data)

    [uint16]$crc = 0xFFFF
    foreach ($byte in $Data) {
        $crc = [uint16]($crc -bxor $byte)
        for ($index = 0; $index -lt 8; $index++) {
            if (($crc -band 1) -ne 0) {
                $crc = [uint16](($crc -shr 1) -bxor 0xA001)
            }
            else {
                $crc = [uint16]($crc -shr 1)
            }
        }
    }
    return $crc
}

try {
    $FunctionCode = [Convert]::ToInt32($Function, 16)
    if ($SlaveId -lt 1 -or $SlaveId -gt 247) { throw 'Slave ID harus 1 sampai 247.' }
    if ($FunctionCode -ne 3 -and $FunctionCode -ne 4) { throw 'Function hanya boleh 03 atau 04 (read-only).' }
    if ($Register -lt 0 -or $Register -gt 65535) { throw 'Register harus 0 sampai 65535.' }
    if ($Count -lt 1 -or $Count -gt 125) { throw 'Jumlah register harus 1 sampai 125.' }

    Write-Host ''
    Write-Host "Membuka $Port @ $BaudRate baud, 8N1..."
    Write-Host ("Request: slave {0}, function 0x{1:X2}, register {2}, count {3}" -f $SlaveId, $FunctionCode, $Register, $Count)
    Write-Host ''

    [byte[]]$request = @(
        $SlaveId,
        $FunctionCode,
        (($Register -shr 8) -band 0xFF),
        ($Register -band 0xFF),
        (($Count -shr 8) -band 0xFF),
        ($Count -band 0xFF)
    )
    $crc = Get-ModbusCrc -Data $request
    [byte[]]$frame = $request + [byte]($crc -band 0xFF) + [byte](($crc -shr 8) -band 0xFF)

    $serial = [System.IO.Ports.SerialPort]::new(
        $Port,
        $BaudRate,
        [System.IO.Ports.Parity]::None,
        8,
        [System.IO.Ports.StopBits]::One
    )
    $serial.ReadTimeout = 1500
    $serial.WriteTimeout = 1500
    $serial.DtrEnable = $false
    $serial.RtsEnable = $false

    try {
        $serial.Open()
        $serial.DiscardInBuffer()
        $serial.DiscardOutBuffer()
        $serial.Write($frame, 0, $frame.Length)
        Write-Host ('TX: ' + (($frame | ForEach-Object { $_.ToString('X2') }) -join ' '))

        $expectedLength = 5 + ($Count * 2)
        $buffer = New-Object byte[] $expectedLength
        $received = 0
        while ($received -lt $expectedLength) {
            $read = $serial.Read($buffer, $received, $expectedLength - $received)
            if ($read -le 0) { break }
            $received += $read
        }
        if ($received -eq 0) {
            throw 'Tidak ada respons. Periksa kabel, COM, baudrate, slave ID, function code, dan register.'
        }

        [byte[]]$reply = $buffer[0..($received - 1)]
        Write-Host ('RX: ' + (($reply | ForEach-Object { $_.ToString('X2') }) -join ' '))
        if ($reply[0] -ne $SlaveId) { throw "Slave ID respons tidak cocok: $($reply[0])" }
        if (($reply[1] -band 0x80) -ne 0) { throw ('Perangkat mengembalikan Modbus exception code 0x' + $reply[2].ToString('X2')) }
        if ($reply[1] -ne $FunctionCode) { throw ('Function respons tidak cocok: 0x' + $reply[1].ToString('X2')) }
        if ($reply.Length -ne $expectedLength) { throw "Panjang respons tidak lengkap: $($reply.Length) byte, diharapkan $expectedLength byte." }

        $responseCrc = Get-ModbusCrc -Data ([byte[]]$reply[0..($reply.Length - 3)])
        if ($reply[$reply.Length - 2] -ne [byte]($responseCrc -band 0xFF) -or $reply[$reply.Length - 1] -ne [byte](($responseCrc -shr 8) -band 0xFF)) {
            throw 'CRC respons tidak valid.'
        }

        Write-Host 'BERHASIL: respons Modbus valid diterima.' -ForegroundColor Green
        if ($Count -eq 2) {
            [byte[]]$rawBytes = $reply[3..6]
            [byte[]]$ieeeBytes = $rawBytes.Clone()
            switch ($ByteOrder) {
                'ABCD' { }
                'BADC' { $ieeeBytes = [byte[]]@($rawBytes[1], $rawBytes[0], $rawBytes[3], $rawBytes[2]) }
                'CDAB' { $ieeeBytes = [byte[]]@($rawBytes[2], $rawBytes[3], $rawBytes[0], $rawBytes[1]) }
                'DCBA' { [Array]::Reverse($ieeeBytes) }
                default { throw "Byte order tidak didukung: $ByteOrder" }
            }
            if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($ieeeBytes) }
            $rawValue = [BitConverter]::ToSingle($ieeeBytes, 0)
            if ([Single]::IsNaN($rawValue) -or [Single]::IsInfinity($rawValue)) { throw 'Nilai float tidak valid.' }

            $finalValue = [double]$rawValue * $Factor
            $shown = $finalValue.ToString('F4', $InvariantCulture)
            Write-Host ''
            Write-Host ("{0}: {1} {2}" -f $Label, $shown, $Unit) -ForegroundColor Cyan
            Write-Host ("Nilai mentah float {0}: {1}; faktor: {2}" -f $ByteOrder, $rawValue.ToString('G9', $InvariantCulture), $Factor.ToString($InvariantCulture))
        }
        else {
            Write-Host 'Nilai DEBIT tidak dihitung karena pembacaan bukan tepat 2 register.' -ForegroundColor Yellow
        }
    }
    finally {
        if ($serial -and $serial.IsOpen) { $serial.Close() }
        if ($serial) { $serial.Dispose() }
    }
}
catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
