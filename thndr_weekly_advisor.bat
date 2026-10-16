<# :
@echo off
title Thndr LIVE Whole-Market EGX Terminal (All 279 Stocks + Graphs + Email Alerts)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ScriptDir = '%~dp0'; $ScriptPath = '%~f0'; $AutoArg = '%1'; Invoke-Expression ([System.IO.File]::ReadAllText('%~f0'))"
if /I not "%1"=="--silent-check" pause
exit /b
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
$PortfolioFile = Join-Path $ScriptDir "thndr_portfolio.json"
$HtmlDashboardFile = Join-Path $ScriptDir "thndr_live_charts.html"
$GoalAmount = 5000.0
$FeeEstimate = 4.0
$DefaultTargetEmail = "michael@mitrixo.com"
$script:PrevPrices = @{}
$script:TickCount = 0

# Load or initialize portfolio state
if (Test-Path $PortfolioFile) {
    try {
        $Portfolio = Get-Content $PortfolioFile -Raw | ConvertFrom-Json
    } catch {
        $Portfolio = $null
    }
}

if (-not $Portfolio) {
    $Portfolio = [PSCustomObject]@{
        CashEGP       = 500.0
        TotalInvested = 500.0
        GoalEGP       = 5000.0
        Holdings      = @()
        EmailConfig   = [PSCustomObject]@{
            Enabled     = $true
            Mode        = "FormSubmit"
            ToEmail     = $DefaultTargetEmail
            FromEmail   = ""
            AppPassword = ""
            SmtpServer  = "smtp.gmail.com"
            SmtpPort    = 587
            LastAlerts  = [PSCustomObject]@{}
        }
    }
    $Portfolio | ConvertTo-Json -Depth 6 | Set-Content $PortfolioFile -Encoding UTF8
}

if (-not ($Portfolio.PSObject.Properties.Name -contains "EmailConfig") -or $null -eq $Portfolio.EmailConfig) {
    $Portfolio | Add-Member -NotePropertyName "EmailConfig" -NotePropertyValue ([PSCustomObject]@{
        Enabled     = $true
        Mode        = "FormSubmit"
        ToEmail     = $DefaultTargetEmail
        FromEmail   = ""
        AppPassword = ""
        SmtpServer  = "smtp.gmail.com"
        SmtpPort    = 587
        LastAlerts  = [PSCustomObject]@{}
    }) -Force
} else {
    if (-not ($Portfolio.EmailConfig.PSObject.Properties.Name -contains "ToEmail") -or [string]::IsNullOrWhiteSpace($Portfolio.EmailConfig.ToEmail)) {
        $Portfolio.EmailConfig | Add-Member -NotePropertyName "ToEmail" -NotePropertyValue $DefaultTargetEmail -Force
    }
    if (-not ($Portfolio.EmailConfig.PSObject.Properties.Name -contains "Mode") -or [string]::IsNullOrWhiteSpace($Portfolio.EmailConfig.Mode)) {
        $Portfolio.EmailConfig | Add-Member -NotePropertyName "Mode" -NotePropertyValue "FormSubmit" -Force
    }
    $Portfolio.EmailConfig.Enabled = $true
}

function Save-Portfolio {
    $Portfolio | ConvertTo-Json -Depth 6 | Set-Content $PortfolioFile -Encoding UTF8
}

function Draw-Bar {
    param([double]$Value, [double]$Max = 100.0, [int]$Width = 10)
    $clamped = [Math]::Max(0.0, [Math]::Min($Max, $Value))
    $filled = [Math]::Round(($clamped / $Max) * $Width)
    $empty = [Math]::Max(0, $Width - $filled)
    return ("#" * $filled) + ("." * $empty)
}

function Send-SellAlertEmail {
    param([string]$Subject, [string]$PlainMessage, [string]$HtmlBody)
    $cfg = $Portfolio.EmailConfig
    $toEmail = if ($cfg.ToEmail) { $cfg.ToEmail } else { $DefaultTargetEmail }
    if (-not $cfg.Enabled) { return $false }

    if ($cfg.Mode -eq "SMTP" -and (-not [string]::IsNullOrWhiteSpace($cfg.FromEmail)) -and (-not [string]::IsNullOrWhiteSpace($cfg.AppPassword))) {
        try {
            $msg = New-Object System.Net.Mail.MailMessage
            $msg.From = $cfg.FromEmail
            $msg.To.Add($toEmail)
            $msg.Subject = $Subject
            $msg.Body = $HtmlBody
            $msg.IsBodyHtml = $true

            $smtp = New-Object System.Net.Mail.SmtpClient($cfg.SmtpServer, [int]$cfg.SmtpPort)
            $smtp.EnableSsl = $true
            $smtp.Credentials = New-Object System.Net.NetworkCredential($cfg.FromEmail, $cfg.AppPassword)
            $smtp.Send($msg)
            return $true
        } catch {
            return $false
        }
    }

    try {
        $payload = @{
            _subject  = $Subject
            _template = "table"
            _captcha  = "false"
            Portfolio = "Thndr 500 -> 5,000 EGP Challenge"
            Alert     = $PlainMessage
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        } | ConvertTo-Json -Depth 4

        $headers = @{
            "Content-Type" = "application/json"
            "Accept"       = "application/json"
            "Referer"      = "https://thndr-egx-advisor.local/"
            "Origin"       = "https://thndr-egx-advisor.local"
        }
        [void](Invoke-RestMethod -Uri "https://formsubmit.co/ajax/$toEmail" -Method Post -Headers $headers -Body $payload -TimeoutSec 15)
        return $true
    } catch {
        return $false
    }
}

function Fetch-MacroAndGoldData {
    $Macro = [PSCustomObject]@{
        USDEGP     = 0.0
        GoldOzUSD  = 0.0
        Gold24kEGP = 0.0
        Gold21kEGP = 0.0
    }
    try {
        $fxBody = '{"symbols":{"tickers":["FX_IDC:USDEGP","TVC:GOLD"]},"columns":["name","close","change"]}'
        $fx = Invoke-RestMethod -Uri "https://scanner.tradingview.com/global/scan" -Method Post -ContentType "application/json" -Body $fxBody -TimeoutSec 10
        foreach ($row in $fx.data) {
            if ($row.s -eq "FX_IDC:USDEGP") { $Macro.USDEGP = [Math]::Round([double]$row.d[1], 2) }
            if ($row.s -eq "TVC:GOLD") { $Macro.GoldOzUSD = [Math]::Round([double]$row.d[1], 2) }
        }
        if ($Macro.USDEGP -gt 0 -and $Macro.GoldOzUSD -gt 0) {
            $Macro.Gold24kEGP = [Math]::Round(($Macro.GoldOzUSD * $Macro.USDEGP) / 31.1034768, 0)
            $Macro.Gold21kEGP = [Math]::Round($Macro.Gold24kEGP * 0.875, 0)
        }
    } catch {}
    return $Macro
}

function Fetch-WholeEGXMarket {
    # Fetches ALL ~279 EGP-denominated stocks across the entire Egyptian Stock Exchange (EGX)
    $BodyObj = @{
        filter = @(
            @{
                left      = "currency"
                operation = "equal"
                right     = "EGP"
            }
        )
        columns = @(
            "name",
            "description",
            "close",
            "change",
            "RSI",
            "Recommend.All",
            "SMA20",
            "SMA50",
            "SMA200",
            "price_earnings_ttm",
            "dividends_yield_current",
            "Value.Traded",
            "MACD.macd",
            "MACD.signal",
            "BB.lower",
            "BB.upper",
            "sector",
            "volume"
        )
        sort = @{
            sortBy    = "Value.Traded"
            sortOrder = "desc"
        }
        range = @(0, 350)
    } | ConvertTo-Json -Depth 5

    $Response = Invoke-RestMethod -Uri "https://scanner.tradingview.com/egypt/scan" -Method Post -ContentType "application/json" -Body $BodyObj -TimeoutSec 15
    $Map = @{}
    $script:TickCount++

    foreach ($item in $Response.data) {
        $d = $item.d
        $ticker = [string]$d[0]
        $name = [string]$d[1]
        $price = if ($null -ne $d[2]) { [double]$d[2] } else { 0.0 }
        $change = if ($null -ne $d[3]) { [double]$d[3] } else { 0.0 }
        $rsi = if ($null -ne $d[4]) { [double]$d[4] } else { 50.0 }
        $rec = if ($null -ne $d[5]) { [double]$d[5] } else { 0.0 }
        $sma20 = if ($null -ne $d[6]) { [double]$d[6] } else { $price }
        $sma50 = if ($null -ne $d[7]) { [double]$d[7] } else { $price }
        $sma200 = if ($null -ne $d[8]) { [double]$d[8] } else { $price }
        $pe = if ($null -ne $d[9]) { [double]$d[9] } else { 0.0 }
        $divYield = if ($null -ne $d[10]) { [double]$d[10] } else { 0.0 }
        $valTraded = if ($null -ne $d[11]) { [double]$d[11] } else { 0.0 }
        $macd = if ($null -ne $d[12]) { [double]$d[12] } else { 0.0 }
        $macdSig = if ($null -ne $d[13]) { [double]$d[13] } else { 0.0 }
        $bbLower = if ($null -ne $d[14]) { [double]$d[14] } else { $price * 0.95 }
        $bbUpper = if ($null -ne $d[15]) { [double]$d[15] } else { $price * 1.05 }
        $sector = if ($null -ne $d[16]) { [string]$d[16] } else { "General" }
        $volume = if ($null -ne $d[17]) { [double]$d[17] } else { 0.0 }

        if ($price -le 0) { continue }

        # Detect live tick movement vs previous scan
        $tickDir = "="
        if ($script:PrevPrices.ContainsKey($ticker)) {
            $oldP = $script:PrevPrices[$ticker]
            if ($price -gt $oldP) { $tickDir = "UP" }
            elseif ($price -lt $oldP) { $tickDir = "DN" }
        }
        $script:PrevPrices[$ticker] = $price

        # Compute Smart Score (0 - 100)
        $score = 50.0
        $reasons = @()
        $plainWhy = ""

        # Liquidity & Quality check (Scans all 279 stocks, prioritizes liquid stocks you can easily buy/sell on Thndr)
        $isLiquid = ($valTraded -ge 10000000 -and $price -ge 1.50 -and $change -gt -4.0)
        if ($valTraded -ge 35000000) {
            $score += 8
        } elseif ($valTraded -lt 5000000) {
            $score -= 25
        }
        if ($change -le -4.0) {
            $score -= 18
        }

        # 1. RSI logic
        if ($rsi -le 33) {
            $score += 20
            $reasons += "Cheap Dip (RSI $([Math]::Round($rsi,0)))"
            $plainWhy = "Stock just had a big discount dip and is ready to bounce back up."
        } elseif ($rsi -gt 33 -and $rsi -le 48) {
            $score += 14
            $reasons += "Good Entry (RSI $([Math]::Round($rsi,0)))"
            $plainWhy = "Price cooled off to a safe, attractive entry point before the next leg up."
        } elseif ($rsi -gt 48 -and $rsi -le 63) {
            $score += 10
            $reasons += "Rising Trend (RSI $([Math]::Round($rsi,0)))"
            $plainWhy = "Buyers are in control and pushing the stock steadily higher."
        } elseif ($rsi -ge 70) {
            $score -= 25
            $reasons += "Too Expensive/Hot (RSI $([Math]::Round($rsi,0)))"
            $plainWhy = "Price jumped too fast and is overheated - high risk of a drop."
        }

        # 2. Moving Average Trend
        if ($price -gt $sma200) {
            $score += 10
            if ($price -gt $sma20 -and $sma20 -gt $sma50) {
                $score += 8
                $reasons += "Strong Uptrend"
            } elseif ($price -lt $sma20) {
                $score += 7
                $reasons += "Dip in Uptrend"
            }
        } else {
            $score -= 12
            if ($price -lt $sma50) {
                $score -= 6
                $reasons += "Downtrend"
            }
        }

        # 3. MACD & Bollinger Bands
        $macdBullish = ($macd -gt $macdSig)
        if ($macdBullish) {
            $score += 8
            $reasons += "MACD Buy"
        } else {
            $score -= 4
        }

        if ($price -le ($bbLower * 1.02)) {
            $score += 7
            $reasons += "At Bottom Band"
        } elseif ($price -ge ($bbUpper * 0.99) -and $rsi -ge 65) {
            $score -= 10
            $reasons += "At Top Ceiling"
        }

        # 4. Technical indicator consensus
        $score += ($rec * 14.0)

        # 5. Valuation & Yield bonus
        if ($pe -gt 0 -and $pe -le 10) {
            $score += 7
            $reasons += "Cheap P/E ($([Math]::Round($pe,1))x)"
        }
        if ($divYield -ge 3.5) {
            $score += 6
            $reasons += "Div $([Math]::Round($divYield,1))%"
        }

        $score = [Math]::Max(5.0, [Math]::Min(99.0, [Math]::Round($score, 1)))

        # Dummy-proof Signal
        $signal = "WAIT / WATCH"
        if ($score -ge 74 -and $rsi -lt 66 -and $isLiquid) {
            $signal = "STRONG BUY"
        } elseif ($score -ge 65 -and $rsi -lt 65 -and $isLiquid) {
            $signal = "BUY"
        } elseif ($rsi -ge 70 -or ($score -le 42)) {
            $signal = "DO NOT BUY / SELL"
        }

        # Calculate 52/Band Range Graph position (0 to 10)
        $bandSpan = [Math]::Max(0.01, ($bbUpper - $bbLower))
        $bandPos = (($price - $bbLower) / $bandSpan) * 100.0
        $priceGraph = Draw-Bar -Value $bandPos -Max 100.0 -Width 8
        $scoreGraph = Draw-Bar -Value $score -Max 100.0 -Width 10

        $targetPrice = [Math]::Round($price * 1.12, 2)
        $stopLoss = [Math]::Round($price * 0.95, 2)

        $Map[$ticker] = [PSCustomObject]@{
            Ticker      = $ticker
            Name        = if ($name.Length -gt 22) { $name.Substring(0, 22) + ".." } else { $name }
            FullName    = $name
            Price       = [Math]::Round($price, 2)
            ChangePct   = [Math]::Round($change, 2)
            TickDir     = $tickDir
            RSI         = [Math]::Round($rsi, 0)
            MACDBull    = $macdBullish
            BBLower     = [Math]::Round($bbLower, 2)
            BBUpper     = [Math]::Round($bbUpper, 2)
            PriceGraph  = "[$priceGraph]"
            ScoreGraph  = "[$scoreGraph]"
            SMA20       = [Math]::Round($sma20, 2)
            SMA50       = [Math]::Round($sma50, 2)
            SMA200      = [Math]::Round($sma200, 2)
            PE          = if ($pe -gt 0) { [Math]::Round($pe, 1) } else { "-" }
            DivYield    = if ($divYield -gt 0) { [Math]::Round($divYield, 1) } else { 0.0 }
            ValTradedM  = [Math]::Round($valTraded / 1000000.0, 1)
            IsLiquid    = $isLiquid
            Score       = $score
            Signal      = $signal
            TargetPrice = $targetPrice
            StopLoss    = $stopLoss
            Sector      = $sector
            Why         = ($reasons -join " + ")
            PlainWhy    = $plainWhy
        }
    }
    return $Map
}

function Evaluate-HoldingsAndTriggerEmails {
    param($MarketMap)

    $HoldingsValue = 0.0
    $HoldingsReport = @()
    $SellTriggersToEmail = @()
    $TodayKey = (Get-Date).ToString("yyyy-MM-dd")

    foreach ($h in $Portfolio.Holdings) {
        $m = $MarketMap[$h.Ticker]
        $livePrice = if ($m) { $m.Price } else { [double]$h.BuyPrice }
        $posValue = [Math]::Round($h.Shares * $livePrice, 2)
        $HoldingsValue += $posValue
        $costBasis = [Math]::Round($h.Shares * $h.BuyPrice, 2)
        $pnlEGP = [Math]::Round($posValue - $costBasis, 2)
        $pnlPct = if ($costBasis -gt 0) { [Math]::Round((($livePrice - $h.BuyPrice) / $h.BuyPrice) * 100, 2) } else { 0.0 }

        $posAction = "KEEP HOLDING"
        $posReason = "Going according to plan. Wait until price hits your Sell Target."
        $targetSell = [Math]::Round($h.BuyPrice * 1.12, 2)
        $stopSell   = [Math]::Round($h.BuyPrice * 0.94, 2)

        if ($pnlPct -ge 12.0) {
            $posAction = "SELL NOW! (PROFIT)"
            $posReason = "CONGRATS! You hit +$pnlPct% profit ($livePrice EGP). Open Thndr & SELL now!"
        } elseif ($m -and $m.RSI -ge 70 -and $pnlPct -ge 4.0) {
            $posAction = "SELL NOW! (PEAKED)"
            $posReason = "Stock is overheated (RSI $($m.RSI)) and you are up +$pnlPct%. Sell & lock in profit!"
        } elseif ($m -and (-not $m.MACDBull) -and $m.RSI -ge 65 -and $pnlPct -ge 6.0) {
            $posAction = "SELL NOW! (REVERSAL)"
            $posReason = "Trend is turning down after your +$pnlPct% gain. Sell now to keep your profit!"
        } elseif ($pnlPct -le -6.0 -and ($m -and $m.Price -lt $m.SMA50)) {
            $posAction = "SELL NOW! (STOP LOSS)"
            $posReason = "Stock dropped $pnlPct% and broke safety support. Sell to protect your cash!"
        } elseif ($m -and $m.Signal -eq "STRONG BUY" -and $pnlPct -le -2.0) {
            $posAction = "BUY MORE (ON SALE)"
            $posReason = "Good company on temporary discount ($pnlPct%). Safe to add more shares."
        }

        $goalProg = Draw-Bar -Value ([Math]::Max(0, $pnlPct + 6)) -Max 18.0 -Width 8

        $itemObj = [PSCustomObject]@{
            Ticker      = $h.Ticker
            Shares      = $h.Shares
            BuyPrice    = "{0:N2}" -f $h.BuyPrice
            LivePrice   = "{0:N2}" -f $livePrice
            ValueEGP    = $posValue
            ProfitEGP   = if ($pnlEGP -ge 0) { "+{0:N2}" -f $pnlEGP } else { "{0:N2}" -f $pnlEGP }
            ProfitPct   = if ($pnlPct -ge 0) { "+{0:N2}%" -f $pnlPct } else { "{0:N2}%" -f $pnlPct }
            TargetBar   = "[$goalProg]"
            SellTarget  = "{0:N2}" -f $targetSell
            StopLoss    = "{0:N2}" -f $stopSell
            DIRECTIVE   = $posAction
            Note        = $posReason
            Sector      = if ($m) { $m.Sector } else { "General" }
        }
        $HoldingsReport += $itemObj

        if ($posAction -like "SELL NOW*") {
            $alertId = "$($h.Ticker)_$TodayKey"
            $alreadySent = $false
            if ($Portfolio.EmailConfig.LastAlerts -and ($Portfolio.EmailConfig.LastAlerts.PSObject.Properties.Name -contains $alertId)) {
                $alreadySent = $true
            }
            if (-not $alreadySent) {
                $SellTriggersToEmail += $itemObj
            }
        }
    }

    if ($SellTriggersToEmail.Count -gt 0 -and $Portfolio.EmailConfig.Enabled) {
        [Console]::Beep(1000, 300)
        [Console]::Beep(1400, 400)
        $tickersList = ($SellTriggersToEmail | ForEach-Object { $_.Ticker }) -join ", "
        $subject = "THNDR SELL ALERT: Time to SELL $tickersList on EGX!"
        $rowsHtml = ""
        $plainLines = @()
        foreach ($st in $SellTriggersToEmail) {
            $plainLines += "$($st.Ticker): $($st.DIRECTIVE) | Shares: $($st.Shares) | Buy: $($st.BuyPrice) EGP -> Live: $($st.LivePrice) EGP ($($st.ProfitEGP) EGP / $($st.ProfitPct)) | $($st.Note)"
            $rowsHtml += "<tr><td style='padding:8px;border:1px solid #ddd;'><b>$($st.Ticker)</b></td><td style='padding:8px;border:1px solid #ddd;'>$($st.Shares)</td><td style='padding:8px;border:1px solid #ddd;'>$($st.BuyPrice) EGP</td><td style='padding:8px;border:1px solid #ddd;'><b>$($st.LivePrice) EGP</b></td><td style='padding:8px;border:1px solid #ddd;'>$($st.ProfitEGP) EGP ($($st.ProfitPct))</td><td style='padding:8px;border:1px solid #ddd;color:#d9534f;'><b>$($st.DIRECTIVE)</b></td><td style='padding:8px;border:1px solid #ddd;'>$($st.Note)</td></tr>"
        }
        $plainSummary = $plainLines -join " || "
        $bodyHtml = "<html><body style='font-family:Segoe UI,Arial,sans-serif;'><h2 style='color:#d9534f;'>Thndr SELL Alert</h2><table style='border-collapse:collapse;width:100%;'>$rowsHtml</table></body></html>"
        $sent = Send-SellAlertEmail -Subject $subject -PlainMessage $plainSummary -HtmlBody $bodyHtml
        if ($sent) {
            if (-not $Portfolio.EmailConfig.LastAlerts) {
                $Portfolio.EmailConfig | Add-Member -NotePropertyName "LastAlerts" -NotePropertyValue ([PSCustomObject]@{}) -Force
            }
            foreach ($st in $SellTriggersToEmail) {
                $aid = "$($st.Ticker)_$TodayKey"
                $Portfolio.EmailConfig.LastAlerts | Add-Member -NotePropertyName $aid -NotePropertyValue (Get-Date -Format "HH:mm:ss") -Force
            }
            Save-Portfolio
        }
    }

    return [PSCustomObject]@{
        HoldingsValue  = $HoldingsValue
        HoldingsReport = $HoldingsReport
    }
}

function Generate-VisualHtmlDashboard {
    param($MarketMap, $MacroData, $Eval)
    $InvestableCash = [Math]::Max(0, $Portfolio.CashEGP - $FeeEstimate)
    $AllStocks = $MarketMap.Values | Sort-Object Score -Descending
    $TopPick = $AllStocks | Where-Object { $_.Price -le $InvestableCash -and $_.Signal -in @("STRONG BUY", "BUY") } | Select-Object -First 1
    if (-not $TopPick) { $TopPick = $AllStocks | Select-Object -First 1 }

    $TotalVal = [Math]::Round($Portfolio.CashEGP + $Eval.HoldingsValue, 2)
    $GoalPct = [Math]::Min(100.0, [Math]::Round(($TotalVal / $GoalAmount) * 100, 1))

    $RowsHtml = ""
    foreach ($s in ($AllStocks | Where-Object { $_.IsLiquid } | Select-Object -First 60)) {
        $badgeColor = if ($s.Signal -eq "STRONG BUY") { "#10b981" } elseif ($s.Signal -eq "BUY") { "#3b82f6" } elseif ($s.Signal -like "*SELL*") { "#ef4444" } else { "#6b7280" }
        $chgColor = if ($s.ChangePct -ge 0) { "#10b981" } else { "#ef4444" }
        $shQty = [Math]::Floor($InvestableCash / $s.Price)
        $RowsHtml += @"
        <tr onclick="loadChart('$($s.Ticker)')" style="cursor:pointer;">
            <td><b>$($s.Ticker)</b><br><small style="color:#9ca3af;">$($s.Name)</small></td>
            <td><b>$("{0:N2}" -f $s.Price) EGP</b></td>
            <td style="color:$chgColor;font-weight:bold;">$(if($s.ChangePct -ge 0){"+$($s.ChangePct)%"}else{"$($s.ChangePct)%"})</td>
            <td>
                <div style="background:#374151;border-radius:4px;width:90px;height:10px;overflow:hidden;display:inline-block;">
                    <div style="background:$badgeColor;width:$($s.Score)%;height:100%;"></div>
                </div>
                <b>$($s.Score)</b>
            </td>
            <td><span style="background:$badgeColor;color:#fff;padding:3px 8px;border-radius:12px;font-size:12px;font-weight:bold;">$($s.Signal)</span></td>
            <td>$(if($shQty -gt 0 -and $s.Signal -like "*BUY*"){"<b>$shQty shares</b> (~$([Math]::Round($shQty*$s.Price,0)) EGP)"}else{"-"})</td>
            <td style="color:#10b981;font-weight:bold;">$("{0:N2}" -f $s.TargetPrice) EGP</td>
            <td style="color:#f59e0b;">$("{0:N2}" -f $s.StopLoss) EGP</td>
            <td style="font-size:12px;color:#d1d5db;">$($s.Why)</td>
        </tr>
"@
    }

    $TopQty = [Math]::Floor($InvestableCash / $TopPick.Price)
    $TopCost = [Math]::Round($TopQty * $TopPick.Price, 2)
    $TopProfit = [Math]::Round($TopQty * ($TopPick.TargetPrice - $TopPick.Price), 2)

    $Html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Thndr Live EGX Visual Command Center (All $($MarketMap.Count) Stocks)</title>
<style>
    body { background:#0f172a; color:#f8fafc; font-family:'Segoe UI',system-ui,sans-serif; margin:0; padding:20px; }
    .grid { display:grid; grid-template-columns: 1fr 1fr; gap:20px; margin-bottom:20px; }
    .card { background:#1e293b; border:1px solid #334155; border-radius:12px; padding:18px; box-shadow:0 4px 15px rgba(0,0,0,0.3); }
    .step-box { background:#064e3b; border:2px solid #10b981; border-radius:12px; padding:18px; }
    table { width:100%; border-collapse:collapse; margin-top:10px; }
    th, td { padding:10px 12px; text-align:left; border-bottom:1px solid #334155; }
    th { background:#0f172a; color:#94a3b8; font-size:12px; text-transform:uppercase; }
    tr:hover { background:#334155; }
    .progress-bar { background:#334155; border-radius:999px; height:22px; width:100%; overflow:hidden; margin:10px 0; }
    .progress-fill { background:linear-gradient(90deg, #10b981, #3b82f6); height:100%; text-align:center; font-size:13px; line-height:22px; font-weight:bold; }
</style>
</head>
<body>
    <h1 style="margin-top:0;color:#38bdf8;">⚡ Thndr Live Whole-Market EGX Visual Dashboard ($($MarketMap.Count) Stocks Scanned)</h1>
    <div class="grid">
        <div class="card">
            <h3 style="margin-top:0;color:#fbbf24;">🎯 Your 500 EGP &rarr; 5,000 EGP Challenge Progress</h3>
            <div style="font-size:26px;font-weight:bold;">$TotalVal EGP <span style="font-size:15px;color:#94a3b8;">/ 5,000 EGP Goal ($GoalPct%)</span></div>
            <div class="progress-bar"><div class="progress-fill" style="width:$([Math]::Max(5, $GoalPct))%;">$GoalPct%</div></div>
            <p style="color:#cbd5e1;margin:6px 0;">💵 Available Cash: <b>$($Portfolio.CashEGP) EGP</b> | 📈 Invested Stocks: <b>$($Eval.HoldingsValue) EGP</b></p>
            <p style="color:#fbbf24;margin:6px 0;">🪙 Live Egypt Gold: <b>24K: $($MacroData.Gold24kEGP) EGP/g</b> | <b>21K: $($MacroData.Gold21kEGP) EGP/g</b> | <b>USD/EGP: $($MacroData.USDEGP)</b></p>
            <p style="color:#34d399;margin:6px 0;">📧 Automatic SELL Email Alerts: <b>ACTIVE &rarr; $($Portfolio.EmailConfig.ToEmail)</b></p>
        </div>
        <div class="step-box">
            <h3 style="margin-top:0;color:#6ee7b7;">✅ DUMMY-PROOF STEP-BY-STEP: WHAT TO DO RIGHT NOW</h3>
            <ol style="font-size:16px;line-height:1.7;margin:0;padding-left:20px;">
                <li>Open the <b>Thndr App</b> on your phone and tap <b>Search 🔍</b>.</li>
                <li>Type <b><code>$($TopPick.Ticker)</code></b> ($($TopPick.FullName)).</li>
                <li>Tap <b>Buy</b> &rarr; Choose <b>Limit Order</b> &rarr; Enter <b>$TopQty shares</b> at <b>$($TopPick.Price) EGP</b> (Total: ~$TopCost EGP).</li>
                <li><b>When to Sell:</b> Sell when price hits <b style="color:#6ee7b7;">$($TopPick.TargetPrice) EGP</b> (gives you <b>+$TopProfit EGP profit</b>). We will also email <b>$($Portfolio.EmailConfig.ToEmail)</b> automatically when it's time to sell!</li>
            </ol>
            <p style="margin-bottom:0;margin-top:10px;color:#a7f3d0;font-size:13px;">💡 <i>Why this stock? $($TopPick.PlainWhy) ($($TopPick.Why))</i></p>
        </div>
    </div>

    <div class="card" style="margin-bottom:20px;">
        <h3 style="margin-top:0;color:#38bdf8;">📊 Live Interactive EGX Price &amp; RSI/MACD Chart (Click any stock below to switch chart)</h3>
        <div id="tv_chart_container" style="height:420px;">
            <iframe id="tv_iframe" src="https://s.tradingview.com/widgetembed/?frameElementId=tv_iframe&symbol=EGX%3A$($TopPick.Ticker)&interval=D&hidesidetoolbar=0&symboledit=1&saveimage=1&toolbarbg=f1f3f6&studies=RSI%40tv-basicstudies%1FMACD%40tv-basicstudies&theme=dark&style=1&timezone=Africa%2FCairo" style="width:100%;height:100%;border:none;border-radius:8px;"></iframe>
        </div>
    </div>

    <div class="card">
        <h3 style="margin-top:0;color:#fbbf24;">📋 Top 60 Most Active EGX Stocks Ranked by AI Buy/Sell Score (Click any row to load its chart above!)</h3>
        <table>
            <thead>
                <tr><th>Ticker / Company</th><th>Live Price</th><th>Day %</th><th>Power Score</th><th>Signal</th><th>How Many to Buy</th><th>Sell Target (+12%)</th><th>Stop-Loss (-5%)</th><th>Why?</th></tr>
            </thead>
            <tbody>
                $RowsHtml
            </tbody>
        </table>
    </div>

    <script>
        function loadChart(ticker) {
            document.getElementById('tv_iframe').src = "https://s.tradingview.com/widgetembed/?frameElementId=tv_iframe&symbol=EGX%3A" + ticker + "&interval=D&hidesidetoolbar=0&symboledit=1&saveimage=1&toolbarbg=f1f3f6&studies=RSI%40tv-basicstudies%1FMACD%40tv-basicstudies&theme=dark&style=1&timezone=Africa%2FCairo";
            window.scrollTo({ top: 180, behavior: 'smooth' });
        }
    </script>
</body>
</html>
"@
    $Html | Set-Content $HtmlDashboardFile -Encoding UTF8
    return $HtmlDashboardFile
}

function Get-MarketHoursCairo {
    try {
        $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("Egypt Standard Time")
        $cNow = [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $tz)
    } catch {
        $cNow = Get-Date
    }
    $day = [int]$cNow.DayOfWeek # 0=Sun .. 4=Thu, 5=Fri, 6=Sat
    $secs = $cNow.Hour * 3600 + $cNow.Minute * 60 + $cNow.Second
    $isEgxDay = ($day -ge 0 -and $day -le 4)

    $preOpenSec = 9 * 3600 + 30 * 60
    $openSec    = 10 * 3600
    $closeSec   = 14 * 3600 + 30 * 60

    $egxState = "CLOSED"
    $nextLabel = ""
    $secsWait = 0

    if ($isEgxDay -and $secs -ge $openSec -and $secs -lt $closeSec) {
        $egxState = "OPEN"
        $secsWait = $closeSec - $secs
        $nextLabel = "Closes Today at 2:30 PM Cairo"
    } elseif ($isEgxDay -and $secs -ge $preOpenSec -and $secs -lt $openSec) {
        $egxState = "PRE-OPEN"
        $secsWait = $openSec - $secs
        $nextLabel = "Main Trading Opens Today at 10:00 AM Cairo"
    } else {
        $egxState = "CLOSED"
        $daysAdd = 0
        if ($isEgxDay -and $secs -lt $openSec) { $daysAdd = 0 }
        elseif ($day -eq 4 -and $secs -ge $closeSec) { $daysAdd = 3 }
        elseif ($day -eq 5) { $daysAdd = 2 }
        elseif ($day -eq 6) { $daysAdd = 1 }
        else { $daysAdd = 1 }
        $secsWait = ($daysAdd * 86400) + ($openSec - $secs)
        $dayWord = if ($daysAdd -eq 0) { "Today" } elseif ($day -in @(4,5,6)) { "Sunday" } else { "Tomorrow" }
        $nextLabel = "Opens $dayWord at 10:00 AM Cairo"
    }

    $ts = [TimeSpan]::FromSeconds([Math]::Max(0, $secsWait))
    $countdownStr = if ($ts.Days -gt 0) { "$($ts.Days)d $($ts.Hours)h $($ts.Minutes)m $($ts.Seconds)s" } else { "$($ts.Hours)h $($ts.Minutes)m $($ts.Seconds)s" }

    # US Market on Thndr (Mon-Fri 4:30 PM - 11:00 PM Cairo)
    $isUsDay = ($day -ge 1 -and $day -le 5)
    $usOpenSec = 16 * 3600 + 30 * 60
    $usCloseSec = 23 * 3600
    $usStatus = "CLOSED (Mon-Fri 4:30 PM - 11:00 PM Cairo)"
    if ($isUsDay -and $secs -ge $usOpenSec -and $secs -lt $usCloseSec) {
        $usRem = [TimeSpan]::FromSeconds($usCloseSec - $secs)
        $usStatus = "OPEN NOW (Closes in $($usRem.Hours)h $($usRem.Minutes)m)"
    } elseif ($isUsDay -and $secs -lt $usOpenSec) {
        $usRem = [TimeSpan]::FromSeconds($usOpenSec - $secs)
        $usStatus = "Opens Today 4:30 PM Cairo (in $($usRem.Hours)h $($usRem.Minutes)m)"
    }

    $goldSpotStatus = if ($day -ge 1 -and $day -le 5) { "OPEN NOW (Mon-Fri 24h Live)" } else { "WEEKEND PAUSE (Opens Mon 1:00 AM)" }

    return [PSCustomObject]@{
        CairoClock     = $cNow.ToString("ddd dd MMM HH:mm:ss") + " Cairo"
        EgxState       = $egxState
        NextLabel      = $nextLabel
        Countdown      = $countdownStr
        UsStatus       = $usStatus
        GoldSpotStatus = $goldSpotStatus
    }
}

function Show-Dashboard {
    param($MarketMap, $MacroData)

    Clear-Host
    $MktHours = Get-MarketHoursCairo
    $PulseIcon = if ($script:TickCount % 2 -eq 0) { "(*)" } else { "(o)" }
    $CurrentGoal = if ($Portfolio.GoalEGP -gt 0) { [double]$Portfolio.GoalEGP } else { $GoalAmount }

    Write-Host "======================================================================================================================" -ForegroundColor Cyan
    Write-Host " $PulseIcon THNDR LIVE WHOLE-MARKET EGX TERMINAL | ALL $($MarketMap.Count) EGP STOCKS | SCAN #$($script:TickCount) | $($MktHours.CairoClock) " -ForegroundColor Yellow
    Write-Host "======================================================================================================================" -ForegroundColor Cyan

    # LIVE MARKET OPEN / CLOSED & COUNTDOWN BANNER
    if ($MktHours.EgxState -eq "OPEN") {
        Write-Host "  [MARKET STATUS] 🟢 EGX STOCK MARKET IS OPEN NOW! ($($MktHours.NextLabel) - $($MktHours.Countdown) left)" -ForegroundColor Green
    } elseif ($MktHours.EgxState -eq "PRE-OPEN") {
        Write-Host "  [MARKET STATUS] 🟡 EGX PRE-OPEN AUCTION SESSION ($($MktHours.NextLabel) - in $($MktHours.Countdown))" -ForegroundColor Yellow
    } else {
        Write-Host "  [MARKET STATUS] 🔴 EGX STOCK MARKET IS CLOSED RIGHT NOW! -> $($MktHours.NextLabel) (Countdown: $($MktHours.Countdown))" -ForegroundColor Red
    }
    Write-Host "  [WHAT IS OPEN?] 1) EGX Stocks: $($MktHours.EgxState) | 2) Thndr AZ-Gold & Clouds: OPEN 24/7 | 3) US Stocks: $($MktHours.UsStatus) | 4) Global Gold: $($MktHours.GoldSpotStatus)" -ForegroundColor Cyan
    Write-Host "----------------------------------------------------------------------------------------------------------------------" -ForegroundColor DarkGray

    $Eval = Evaluate-HoldingsAndTriggerEmails -MarketMap $MarketMap
    $HoldingsValue = $Eval.HoldingsValue
    $HoldingsReport = $Eval.HoldingsReport

    $TotalPortfolioValue = [Math]::Round($Portfolio.CashEGP + $HoldingsValue, 2)
    $NetProfit = [Math]::Round($TotalPortfolioValue - $Portfolio.TotalInvested, 2)
    $GoalPct = [Math]::Min(100.0, [Math]::Round(($TotalPortfolioValue / $CurrentGoal) * 100, 1))
    $ProgressBar = Draw-Bar -Value $GoalPct -Max 100.0 -Width 25

    $TotalWealth500k = [Math]::Round(460000.0 + $TotalPortfolioValue, 2)
    $WealthPct = [Math]::Min(100.0, [Math]::Round(($TotalWealth500k / 500000.0) * 100, 1))
    $WealthBar = Draw-Bar -Value $WealthPct -Max 100.0 -Width 25
    $LeftTo500k = [Math]::Max(0, [Math]::Round(500000.0 - $TotalWealth500k, 0))

    Write-Host "  500K WEALTH    : [$WealthBar] $WealthPct% ($TotalWealth500k / 500,000 EGP | Only $LeftTo500k EGP left!)" -ForegroundColor Yellow
    Write-Host "  INCOME DATES   : 5th: +887.50 (60K) | 12th: +475 (30K) | 14th: +2,000 (Strike Gym) | 15th: +5,175 (360K) | 18th: +147.92 (10K) | Qtr 19th: +8,000 (Inzan)" -ForegroundColor Cyan
    Write-Host "  THNDR GOAL     : [$ProgressBar] $GoalPct% ($TotalPortfolioValue EGP / $CurrentGoal EGP) [Press 9 to Edit Goal]" -ForegroundColor White
    Write-Host "  YOUR WALLET    : Cash: $([Math]::Round($Portfolio.CashEGP, 2)) EGP  |  Stocks Owned: $([Math]::Round($HoldingsValue, 2)) EGP  |  Total Profit: $(if($NetProfit -ge 0){"+$NetProfit"}else{"$NetProfit"}) EGP" -ForegroundColor Gray
    Write-Host "  LIVE GOLD & FX : USD/EGP: $($MacroData.USDEGP) EGP  |  24K Gold: $($MacroData.Gold24kEGP) EGP/g  |  21K Gold: $($MacroData.Gold21kEGP) EGP/g  |  Email: $($Portfolio.EmailConfig.ToEmail)" -ForegroundColor DarkYellow
    Write-Host ""

    # DUMMY-PROOF STEP-BY-STEP BOX AT THE VERY TOP
    $InvestableCash = [Math]::Max(0, $Portfolio.CashEGP - $FeeEstimate)
    $AllStocks = $MarketMap.Values | Sort-Object Score -Descending
    $TopBuy = $AllStocks | Where-Object { $_.Price -le $InvestableCash -and $_.Signal -in @("STRONG BUY", "BUY") -and $_.IsLiquid } | Select-Object -First 1
    $UrgentSells = $HoldingsReport | Where-Object { $_.DIRECTIVE -like "SELL NOW*" }

    Write-Host "======================================================================================================================" -ForegroundColor Green
    Write-Host " >>> DUMMY-PROOF GUIDE: WHAT SHOULD YOU DO RIGHT NOW? <<<" -ForegroundColor Yellow
    Write-Host "======================================================================================================================" -ForegroundColor Green

    if ($MktHours.EgxState -ne "OPEN") {
        Write-Host "  [!] IMPORTANT: EGX STOCKS ARE CURRENTLY CLOSED ($($MktHours.NextLabel) in $($MktHours.Countdown))!" -ForegroundColor Yellow
        Write-Host "      Do NOT place a 'Market Order' on Thndr right now (it will fail while closed)." -ForegroundColor Yellow
        Write-Host "      -> Option A: Place a 'LIMIT ORDER' on Thndr at the exact price below (Thndr queues it for 10:00 AM open!)." -ForegroundColor White
        Write-Host "      -> Option B: Buy what IS open right now 24/7 on Thndr ('AZ-Gold' or 'Thndr Clouds' savings) or US Stocks ($($MktHours.UsStatus))." -ForegroundColor White
        Write-Host ""
    }

    if ($UrgentSells.Count -gt 0) {
        foreach ($us in $UrgentSells) {
            Write-Host "  [!] URGENT STEP 1 (SELL FOR PROFIT/SAFETY): Open Thndr -> Tap '$($us.Ticker)' -> SELL all $($us.Shares) shares @ $($us.LivePrice) EGP!" -ForegroundColor Red
            Write-Host "      Reason: $($us.Note)" -ForegroundColor White
        }
    } elseif ($HoldingsReport.Count -gt 0) {
        Write-Host "  [OK] YOUR OWNED STOCKS ARE SAFE: Do NOT sell right now. Keep holding until they hit their Sell Target price below." -ForegroundColor Cyan
    }

    if ($null -ne $TopBuy) {
        $qty = [Math]::Floor($InvestableCash / $TopBuy.Price)
        $cost = [Math]::Round($qty * $TopBuy.Price, 2)
        $profitEst = [Math]::Round($qty * ($TopBuy.TargetPrice - $TopBuy.Price), 2)
        $rem = [Math]::Round($Portfolio.CashEGP - $cost, 2)

        Write-Host "  [STEP 1] Open the Thndr app on your phone and tap the Search icon." -ForegroundColor White
        Write-Host "  [STEP 2] Type '$($TopBuy.Ticker)' ($($TopBuy.FullName))." -ForegroundColor White
        if ($MktHours.EgxState -eq "OPEN") {
            Write-Host "  [STEP 3] Tap BUY -> Select 'Limit Order' -> Buy $qty shares at $($TopBuy.Price) EGP (Costs ~$cost EGP - Executes Now!)." -ForegroundColor Green
        } else {
            Write-Host "  [STEP 3] Tap BUY -> Switch Order Type to 'LIMIT PRICE' -> Enter $($TopBuy.Price) EGP for $qty shares (~$cost EGP - Queues for 10:00 AM Open!)." -ForegroundColor Green
        }
        Write-Host "  [STEP 4] WHY? $($TopBuy.PlainWhy)" -ForegroundColor Gray
        Write-Host "  [STEP 5] WHEN TO SELL: Sell at $($TopBuy.TargetPrice) EGP for +$profitEst EGP profit! (We'll email $($Portfolio.EmailConfig.ToEmail) when it hits!)" -ForegroundColor Yellow
        if ($rem -ge 10) {
            Write-Host "  [STEP 6] Put your leftover $rem EGP into 'Thndr Clouds' or 'AZ-Gold' (Open 24/7) so zero money sits idle." -ForegroundColor DarkCyan
        }
    } else {
        Write-Host "  [WAIT] You don't have enough uninvested cash ($($Portfolio.CashEGP) EGP) for a new buy right now. Wait for your stocks to hit Sell Target or add your weekly deposit (Option 3)!" -ForegroundColor Yellow
    }
    Write-Host "======================================================================================================================" -ForegroundColor Green
    Write-Host ""

    # SECTION 1: OWNED STOCKS
    if ($HoldingsReport.Count -gt 0) {
        Write-Host " [1] YOUR STOCKS ON THNDR (LIVE PROFIT TRACKER & SELL SIGNALS)" -ForegroundColor Yellow
        $HoldingsReport | Select-Object Ticker, Shares, BuyPrice, LivePrice, ProfitEGP, ProfitPct, TargetBar, SellTarget, StopLoss, DIRECTIVE | Format-Table -AutoSize | Out-String | Write-Host
    }

    # SECTION 2: WHOLE MARKET TOP 12 WITH VISUAL BARS
    Write-Host " [2] TOP 12 BUY OPPORTUNITIES OUT OF ALL $($MarketMap.Count) EGX STOCKS (WITH VISUAL SCORE & PRICE GRAPHS)" -ForegroundColor Yellow
    $ScannerTable = $AllStocks | Where-Object { $_.Price -le [Math]::Max(495, $InvestableCash) -and $_.IsLiquid } | Select-Object -First 12 | ForEach-Object {
        $sharesCanBuy = [Math]::Floor($InvestableCash / $_.Price)
        $moveArrow = if ($_.TickDir -eq "UP") { "^" } elseif ($_.TickDir -eq "DN") { "v" } elseif ($_.ChangePct -gt 0) { "+" } else { "-" }
        [PSCustomObject]@{
            "Ticker"       = "$moveArrow $($_.Ticker)"
            "Price (EGP)"  = "{0:N2}" -f $_.Price
            "Day %"        = if ($_.ChangePct -ge 0) { "+{0:N2}%" -f $_.ChangePct } else { "{0:N2}%" -f $_.ChangePct }
            "Power Graph"  = "$($_.ScoreGraph) $($_.Score)"
            "Price Zone"   = "$($_.PriceGraph) RSI:$($_.RSI)"
            "ACTION"       = $_.Signal
            "Buy Now"      = if ($sharesCanBuy -gt 0 -and $_.Signal -in @("STRONG BUY","BUY")) { "$sharesCanBuy sh (~$([Math]::Round($sharesCanBuy * $_.Price, 0)) EGP)" } else { "Wait" }
            "Sell Target"  = "{0:N2} EGP" -f $_.TargetPrice
            "Why"          = $_.Why
        }
    }
    $ScannerTable | Format-Table -AutoSize | Out-String | Write-Host
    return $Eval
}

# Handle silent background scheduled check (--silent-check)
if ($AutoArg -eq "--silent-check") {
    $MarketData = Fetch-WholeEGXMarket
    [void](Evaluate-HoldingsAndTriggerEmails -MarketMap $MarketData)
    exit 0
}

# Initial load
Write-Host "[*] Connecting to Egyptian Stock Exchange (EGX) & scanning all ~279 stocks..." -ForegroundColor Cyan
$MacroData = Fetch-MacroAndGoldData
$MarketData = Fetch-WholeEGXMarket

while ($true) {
    $Eval = Show-Dashboard -MarketMap $MarketData -MacroData $MacroData
    Write-Host " CONTROLS:" -ForegroundColor White
    Write-Host "  [G] OPEN VISUAL CHARTS & GRAPHS IN BROWSER (Interactive Candlestick Charts + Full Market Table!)" -ForegroundColor Green
    Write-Host "  [L] LIVE MOVING STREAM MODE (Numbers & Market Countdown tick live every 5 seconds on screen!)" -ForegroundColor Yellow
    Write-Host "  [S] Search / Inspect ANY of the $($MarketData.Count) EGX Stocks on Thndr" -ForegroundColor Cyan
    Write-Host "  [1] I Bought a Stock   |  [2] I Sold a Stock   |  [3] Add Weekly Deposit   |  [4] Refresh Now"
    Write-Host "  [5] Reset Portfolio (Keeps Email Config)       |  [6] Test/Setup Email ($($Portfolio.EmailConfig.ToEmail))"
    Write-Host "  [8] Turn On 15-Min Background Email Watcher    |  [9] Edit Challenge Goal  |  [Q] Quit"
    Write-Host ""
    $choice = (Read-Host "Type an option (G, L, S, 1-9, or Q)").Trim().ToUpper()

    if ($choice -in @("Q", "EXIT")) {
        break
    } elseif ($choice -eq "G") {
        Write-Host "[*] Generating interactive visual charts for all $($MarketData.Count) EGX stocks..." -ForegroundColor Cyan
        $htmlPath = Generate-VisualHtmlDashboard -MarketMap $MarketData -MacroData $MacroData -Eval $Eval
        Start-Process $htmlPath
    } elseif ($choice -eq "L") {
        Write-Host ""
        Write-Host "[*] ENTERING LIVE MOVING TICKER MODE (Updates every 5 seconds! Press ANY KEY to return to menu)..." -ForegroundColor Green
        Start-Sleep -Seconds 1
        while (-not [Console]::KeyAvailable) {
            $MacroData = Fetch-MacroAndGoldData
            $MarketData = Fetch-WholeEGXMarket
            [void](Show-Dashboard -MarketMap $MarketData -MacroData $MacroData)
            Write-Host " ⚡ [LIVE STREAM RUNNING - SCAN #$($script:TickCount)] Numbers updating live every 5s... Press ANY KEY to open menu." -ForegroundColor Green
            for ($i = 0; $i -lt 25; $i++) {
                if ([Console]::KeyAvailable) { break }
                Start-Sleep -Milliseconds 200
            }
        }
        if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
    } elseif ($choice -eq "S") {
        $q = (Read-Host "Enter ANY EGX Ticker or Company Name (e.g. COMI, FWRY, Telecom, Cement)").Trim().ToUpper()
        if ($q) {
            $matches = $MarketData.Values | Where-Object { $_.Ticker -like "*$q*" -or $_.FullName.ToUpper() -like "*$q*" } | Sort-Object Score -Descending
            if ($matches) {
                Write-Host ""
                $matches | Select-Object Ticker, FullName, Price, ChangePct, RSI, Score, Signal, TargetPrice, StopLoss, ValTradedM, Why | Format-Table -AutoSize | Out-String | Write-Host
            } else {
                Write-Host "No EGX stock matched '$q'." -ForegroundColor Red
            }
            Read-Host "Press Enter to return to dashboard"
        }
    } elseif ($choice -eq "1") {
        $t = (Read-Host "Enter Ticker you bought on Thndr (e.g. EGAL, MFPC, ORWE)").Trim().ToUpper()
        $sStr = Read-Host "Enter Number of Shares bought"
        $pStr = Read-Host "Enter Buy Price per share in EGP (Press Enter to use live price)"
        [int]$shares = 0
        [void][int]::TryParse($sStr, [ref]$shares)
        if ($shares -gt 0 -and $t) {
            [double]$buyPrice = 0
            if ([string]::IsNullOrWhiteSpace($pStr) -and $MarketData.ContainsKey($t)) {
                $buyPrice = $MarketData[$t].Price
            } else {
                [void][double]::TryParse($pStr, [ref]$buyPrice)
            }
            if ($buyPrice -gt 0) {
                $cost = [Math]::Round(($shares * $buyPrice) + $FeeEstimate, 2)
                $existing = $Portfolio.Holdings | Where-Object { $_.Ticker -eq $t }
                if ($existing) {
                    $totalSh = $existing.Shares + $shares
                    $avgPx = (($existing.Shares * $existing.BuyPrice) + ($shares * $buyPrice)) / $totalSh
                    $existing.Shares = $totalSh
                    $existing.BuyPrice = [Math]::Round($avgPx, 2)
                } else {
                    $Portfolio.Holdings += [PSCustomObject]@{
                        Ticker   = $t
                        Shares   = $shares
                        BuyPrice = [Math]::Round($buyPrice, 2)
                    }
                }
                $Portfolio.CashEGP = [Math]::Max(0, [Math]::Round($Portfolio.CashEGP - $cost, 2))
                Save-Portfolio
            }
        }
    } elseif ($choice -eq "2") {
        $t = (Read-Host "Enter Ticker you SOLD on Thndr").Trim().ToUpper()
        $existing = $Portfolio.Holdings | Where-Object { $_.Ticker -eq $t }
        if ($existing) {
            $sStr = Read-Host "Enter Shares sold (Press Enter to sell all $($existing.Shares) shares)"
            [int]$sharesSold = $existing.Shares
            if (-not [string]::IsNullOrWhiteSpace($sStr)) {
                [void][int]::TryParse($sStr, [ref]$sharesSold)
            }
            $pStr = Read-Host "Enter Sell Price per share in EGP (Press Enter to use live price)"
            [double]$sellPrice = $existing.BuyPrice
            if ([string]::IsNullOrWhiteSpace($pStr) -and $MarketData.ContainsKey($t)) {
                $sellPrice = $MarketData[$t].Price
            } else {
                [void][double]::TryParse($pStr, [ref]$sellPrice)
            }
            $proceeds = [Math]::Max(0, [Math]::Round(($sharesSold * $sellPrice) - $FeeEstimate, 2))
            $Portfolio.CashEGP = [Math]::Round($Portfolio.CashEGP + $proceeds, 2)
            if ($sharesSold -ge $existing.Shares) {
                $Portfolio.Holdings = @($Portfolio.Holdings | Where-Object { $_.Ticker -ne $t })
            } else {
                $existing.Shares -= $sharesSold
            }
            Save-Portfolio
        } else {
            Write-Host "Ticker $t not found in your holdings." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    } elseif ($choice -eq "3") {
        $dStr = Read-Host "Enter deposit amount in EGP (Press Enter for 500 EGP)"
        [double]$dep = 500.0
        if (-not [string]::IsNullOrWhiteSpace($dStr)) {
            [void][double]::TryParse($dStr, [ref]$dep)
        }
        if ($dep -gt 0) {
            $Portfolio.CashEGP = [Math]::Round($Portfolio.CashEGP + $dep, 2)
            $Portfolio.TotalInvested = [Math]::Round($Portfolio.TotalInvested + $dep, 2)
            Save-Portfolio
        }
    } elseif ($choice -eq "4") {
        Write-Host "[*] Scanning all $($MarketData.Count) EGX stocks..." -ForegroundColor Cyan
        $MacroData = Fetch-MacroAndGoldData
        $MarketData = Fetch-WholeEGXMarket
    } elseif ($choice -eq "5") {
        $savedEmailCfg = $Portfolio.EmailConfig
        if ($savedEmailCfg) {
            $savedEmailCfg | Add-Member -NotePropertyName "LastAlerts" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        $rStr = Read-Host "Enter starting cash in EGP after reset (Press Enter for 500 EGP)"
        [double]$startCash = 500.0
        if (-not [string]::IsNullOrWhiteSpace($rStr)) {
            [void][double]::TryParse($rStr, [ref]$startCash)
        }
        $Portfolio.CashEGP = [Math]::Round($startCash, 2)
        $Portfolio.TotalInvested = [Math]::Round($startCash, 2)
        $Portfolio.Holdings = @()
        $Portfolio.EmailConfig = $savedEmailCfg
        Save-Portfolio
        Write-Host "[+] Portfolio reset to $startCash EGP! Your email config ($($Portfolio.EmailConfig.ToEmail)) was kept intact." -ForegroundColor Green
        Start-Sleep -Seconds 2
    } elseif ($choice -eq "6") {
        Write-Host "[*] Dispatching test alert to $($Portfolio.EmailConfig.ToEmail) ..." -ForegroundColor Cyan
        $ok = Send-SellAlertEmail -Subject "Thndr Live Sell Alert Test - Connected!" -PlainMessage "Your Thndr Live BUY/SELL Advisor is connected to $($Portfolio.EmailConfig.ToEmail)!" -HtmlBody "<h3>Connected!</h3>"
        if ($ok) {
            Write-Host "[+] Sent to $($Portfolio.EmailConfig.ToEmail)! Check your inbox (and click Activate if first time)." -ForegroundColor Green
        }
        Read-Host "Press Enter to continue"
    } elseif ($choice -eq "8") {
        $taskName = "ThndrLiveSellEmailMonitor"
        $cmdToRun = "`"$ScriptPath`" --silent-check"
        schtasks /Create /SC MINUTE /MO 15 /TN $taskName /TR $cmdToRun /F | Out-Null
        Write-Host "[+] Windows Background Task '$taskName' installed (checks every 15m & emails $($Portfolio.EmailConfig.ToEmail))!" -ForegroundColor Green
        Read-Host "Press Enter to continue"
    } elseif ($choice -eq "9") {
        $gStr = Read-Host "Enter your new Challenge Goal target in EGP (Current: $GoalAmount EGP)"
        [double]$newG = 0
        if ([double]::TryParse($gStr, [ref]$newG) -and $newG -gt 0) {
            $GoalAmount = [Math]::Round($newG, 2)
            $Portfolio | Add-Member -NotePropertyName "GoalEGP" -NotePropertyValue $GoalAmount -Force
            Save-Portfolio
            Write-Host "[+] Challenge Goal updated to $GoalAmount EGP!" -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
    }
}
