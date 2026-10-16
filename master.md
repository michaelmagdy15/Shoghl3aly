# ⚡ Thndr EGX Pro — Live Whole-Market Advisor, Market Hours Radar & 24/7 Cloud Worker

> **Custom Live iPhone 15 Pro Web App URL:** [https://thndr-egx-pro.web.app](https://thndr-egx-pro.web.app)  
> **Firebase Project:** `faa-test-guide-v2` (Hosting target: `thndr-egx-pro`, Cloud Worker codebase: `thndr-worker`)  
> **GitHub Repository:** [https://github.com/michaelmagdy15/Shoghl3aly.git](https://github.com/michaelmagdy15/Shoghl3aly.git)  
> **Alert Recipient Email:** `michael@mitrixo.com`

---

## 🌟 System Overview

**Thndr EGX Pro** is an end-to-end investment intelligence & portfolio execution system built for the **Egyptian Stock Exchange (EGX)** and **Thndr App** to grow your weekly investments (starting at **500 EGP/week** toward an adjustable target, initially **5,000 EGP**, customizable up to **50,000+ EGP**).

It runs across **three synchronized layers**:
1. **📱 iPhone 15 Pro Progressive Web App (`https://thndr-egx-pro.web.app`):**
   - Full-screen native iOS dark-mode experience with Dynamic Island & Home Indicator safe areas.
   - **Live 1-Second Market Open/Closed Radar & Countdown Clock (Cairo Time):** Never get surprised by a rejected Market Order when EGX is closed! Shows exact open/close status, live countdown (`1d 21h 50m 12s`), and a real-time **"What Is Open on Thndr Right Now?"** matrix.
   - **Hourly iPhone Home Screen Web Push Notifications (`public/sw.js` + VAPID Web Push):** Native iOS 16.4+/17/18+ Home Screen push notifications every hour + instant push alerts when any owned stock triggers a **SELL NOW** signal.
   - **Adjustable Challenge Goal:** Edit your target portfolio goal (e.g., `2,500 EGP`, `5,000 EGP`, `10,000 EGP`, `50,000 EGP`) and weekly deposit amount anytime.
2. **☁️ 24/7 Firebase Cloud Worker (`functions/index.js`):**
   - Runs automatically **every hour (`0 * * * *` Cairo Time)** on Google Cloud (`us-central1`).
   - Scans all **279 EGP-denominated stocks** on the Egyptian Stock Exchange + live **24K/21K Gold (EGP/gram)** + **USD/EGP**.
   - Evaluates your owned stocks 24/7 and dispatches **instant SELL Alert Emails to `michael@mitrixo.com`** + **iPhone Web Push Notifications** whenever a position hits its **+12% Take-Profit Target**, becomes **Overbought (`RSI >= 70`)**, reverses on **MACD**, or breaches its **-6% Stop-Loss**.
3. **💻 Windows Desktop Live Terminal (`thndr_weekly_advisor.bat`):**
   - One-click `.bat` script on your Desktop (`C:\Users\Mi5a\Desktop\thndr_weekly_advisor.bat`) and in the repo (`thndr_weekly_advisor.bat`).
   - Features Live 5-Second Streaming Mode (`[L]`), Interactive Browser Candlestick/RSI/MACD Charts (`[G]`), Whole-Market Search (`[S]`), Market Open/Closed Countdown Radar, Portfolio Reset that preserves your `michael@mitrixo.com` email config (`[5]`), and Adjustable Challenge Goal (`[9]`).

---

## 🕒 Live Market Hours & "What Is Open Right Now?" Guide (Cairo Time)

One of the most common pitfalls on Thndr is trying to place a **Market Order** on an Egyptian stock when the Egyptian Stock Exchange is closed. Both the iPhone Web App and the Desktop `.bat` Terminal now display a **live 1-second countdown** and automatically adjust your Step-by-Step instructions based on whether EGX is open or closed:

| Market / Asset on Thndr | Trading Days | Live Trading Hours (Cairo Time) | What Happens When Closed? |
| :--- | :--- | :--- | :--- |
| **🇪🇬 EGX Stocks (All 279 EGP Stocks)** | **Sunday – Thursday** | **10:00 AM – 2:30 PM** *(Pre-open auction: 9:30 AM – 10:00 AM)* | **Closed Friday & Saturday** + after 2:30 PM. Do **NOT** use a *Market Order* while closed (Thndr rejects it). Instead, switch Order Type to **Limit Price** on Thndr to queue your order for the 10:00 AM open! |
| **🪙 Thndr Gold & Savings Funds (`AZ-Gold`, `Thndr Clouds`, `CMS`)** | **24/7 Order Queue** | **Open 24/7** *(Executes next Sun–Thu 11:00 AM cut-off)* | You can submit Buy/Invest orders **anytime 24/7** (even on Friday/Saturday weekends) so idle cash earns daily EGP returns or tracks Gold. |
| **🇺🇸 US Stocks on Thndr (NYSE / NASDAQ)** | **Monday – Friday** | **4:30 PM – 11:00 PM** *(Pre-Market: 11:00 AM – 4:30 PM)* | Open on **Fridays** when EGX is closed! |
| **🌍 Global Gold Spot (24K / 21K EGP) & Forex** | **Monday – Friday** | **24 Hours / Day** *(Closes Fri 11:59 PM, Opens Mon 1:00 AM)* | Live international gold ounce & USD/EGP pricing all week through Friday night. |

---

## 📲 How to Install on iPhone 15 Pro & Enable Hourly Notifications

1. Open **Safari** on your **iPhone 15 Pro** and go to:  
   👉 **[https://thndr-egx-pro.web.app](https://thndr-egx-pro.web.app)**
2. Tap the **Share** button at the bottom of Safari (square with arrow pointing up).
3. Scroll down and tap **"Add to Home Screen"** &rarr; Tap **Add**.
4. Launch **Thndr Pro** directly from your **iPhone 15 Pro Home Screen** (it opens full-screen like a native iOS app).
5. Tap the blue **"🔔 Enable Hourly iPhone Push"** button on the Home tab (or inside the **Goal & Email** tab) and tap **Allow** when iOS asks for notification permission.
6. You will immediately receive a confirmation notification banner on your iPhone, followed by **hourly EGX market & stock pick notifications** + **instant SELL NOW alerts**!

---

## 🧠 How the AI Scoring & Buy/Sell Engine Works (All 279 EGX Stocks)

Every scan queries the live TradingView Egypt Exchange feed (`https://scanner.tradingview.com/egypt/scan`) across all **279 EGP-listed stocks** and grades each stock from **0 to 100**:

- **Liquidity Filter (`isLiquid`):** Requires `Value.Traded >= 10,000,000 EGP/day`, `Price >= 1.50 EGP`, and `Day Change > -4.0%` so your money never gets trapped in illiquid penny stocks.
- **RSI (14) Price Thermometer:**
  - `RSI <= 33`: **Oversold Dip (`+20 pts`)** — High-probability bounce setup.
  - `RSI 34–48`: **Healthy Pullback (`+14 pts`)** — Optimal swing entry.
  - `RSI 49–63`: **Rising Momentum (`+10 pts`)** — Trend continuation.
  - `RSI >= 70`: **Overbought Peak (`-25 pts`)** — Triggers `SELL / AVOID`.
- **Moving Average Alignment (`SMA20`, `SMA50`, `SMA200`):** Rewards stocks trading above their 200-day and 50-day uptrends (`+18 pts`).
- **MACD Bullish Crossover & Bollinger Bands:** Adds `+8 pts` when `MACD > Signal` and `+7 pts` near the lower Bollinger support band.
- **Valuation & Dividend Bonus:** Rewards profitable companies with `P/E <= 10x` (`+7 pts`) and `Dividend Yield >= 3.5%` (`+6 pts`).

### Automatic SELL Triggers (24/7 Email + iPhone Push)
Whenever you log a stock purchase, the system monitors it continuously and alerts you to **SELL NOW** when any of these 4 conditions hit:
1. **🎯 Take-Profit Target (`+12%` Gain):** Locks in compounding swing gains toward your Challenge Goal.
2. **🔥 Overbought Peak (`RSI >= 70` with `+4%+` Profit):** Sells into strength before a reversal.
3. **📉 MACD Bearish Reversal (`MACD < Signal` with `RSI >= 65` and `+6%+` Profit):** Protects gains when momentum fades.
4. **🛡️ Safety Stop-Loss (`-6%` Drop below `SMA50`):** Cuts losers early to protect your capital.

---

## 🏦 NBE `460,000 EGP` Certificates + Strike Gym + Inzan Athletics &rarr; `500,000 EGP` Master Plan

Your app now tracks all **4 of your National Bank of Egypt (NBE) Platinum Certificates (`460,000 EGP` total)**, your **Strike Gym monthly tech pay (`2,000 EGP` on the 14th)**, and your **Inzan Athletics quarterly pay (`8,000 EGP` every 3 months on the 19th)** toward your **`500,000 EGP`** goal:

| Date / Schedule | Source / Certificate ID | Principal | Rate | Opened Date | Maturity Date | **Cash Inflow** |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **5th of Every Month** | NBE Platinum `#1397480890284900075` | `60,000 EGP` | `17.75%` | `04 Oct 2026` | **`05 Oct 2029`** | **`+887.50 EGP / mo`** |
| **12th of Every Month** | NBE Step-Down `#1397980890284900037` | `30,000 EGP` | `19.00%` | `11 Aug 2024` | **`12 Aug 2028`** | **`+475.00 EGP / mo`** |
| **14th of Every Month** | **💪 Strike Gym (Tech Help)** | — | — | Recurring | Monthly | **`+2,000.00 EGP / mo`** |
| **15th of Every Month** | NBE Platinum `#1397480890284900064` | `360,000 EGP` | `17.25%` | `14 Jun 2026` | **`15 Jun 2029`** | **`+5,175.00 EGP / mo`** |
| **18th of Every Month** | NBE Platinum `#1397480890284900086` | `10,000 EGP` | `17.75%` | `15 Oct 2026` | **`18 Oct 2029`** | **`+147.92 EGP / mo`** |
| **Quarterly (19 Nov, 19 Feb, 19 May, 19 Aug)** | **🏆 Inzan Athletics** | — | — | `19 Aug 2026` | Quarterly | **`+8,000.00 EGP / qtr`** *(`~2,666.67/mo`)* |
| **TOTAL** | **`460,000 EGP` Base Principal** | **`460,000 EGP`** | **`17.44%` avg** | — | `2028–2029` | **`8,685.42 EGP / mo` + `8,000 EGP / qtr` (`~11,352 EGP/mo` avg)** |

---

## ✈️ Airbus A320 / Boeing 737 Type Rating USD & Gold Protection + 🔒 6-Digit Private Keypass

- **🔒 Private 6-Digit Keypass Lock (`001919`):**
  - Both the **iPhone 15 Pro Web App UI** ([`public/index.html`](file:///c:/Users/Mi5a/Documents/antigravity/intelligent-maxwell/public/index.html)) and the **24/7 Cloud Worker API** ([`functions/index.js`](file:///c:/Users/Mi5a/Documents/antigravity/intelligent-maxwell/functions/index.js)) are locked behind a **6-digit iPhone keypad screen** verified via SHA-256 hash (`13db93d3dbe3bb864bd21ce8298388c6d2588fac81e8824205fb77412888e6fe`) so the plaintext code is never exposed in source code.
  - Tap the **🔒 Lock** button in the top-right header anytime to re-lock the screen immediately.
- **✈️ Live Type Rating USD & 24K Gold Equivalent Counter:**
  - Automatically converts your total net wealth (`NBE Certificates + NBE 4th Daily Fund + Thndr Portfolio`) into **live US Dollars (`$ USD`)** and **24K Pure Gold Grams (`g`)** using real-time `FX_IDC:USDEGP` and `TVC:GOLD` rates.
  - Includes a **`🎯 Edit Type Rating Target`** button to switch between Milestone 1 (`500,000 EGP`), Full Sim Package (`750,000 EGP`), or Full Sim + Base Training (`900,000 EGP`).

---

## 📁 Repository Structure

```text
intelligent-maxwell/
├── master.md                      # Complete system architecture & user guide
├── thndr_weekly_advisor.bat       # Windows Desktop Live EGX Terminal + Chart Generator
├── firebase.json                  # Firebase Hosting (thndr-egx-pro) & Functions (thndr-worker) config
├── .firebaserc                    # Firebase project mapping (faa-test-guide-v2)
├── public/
│   ├── index.html                 # iPhone 15 Pro PWA with 6-Digit PIN Lock, Market Radar, NBE & Type Rating Tracker
│   ├── manifest.json              # iOS Standalone Home Screen Web App Manifest
│   └── sw.js                      # iOS 16.4+/iPhone 15 Pro Web Push Service Worker
└── functions/
    ├── package.json               # Cloud Worker dependencies (firebase-functions, firebase-admin, web-push)
    └── index.js                   # 24/7 Hourly Cloud Worker + Passcode-Protected Live API (/api/advisor)
```
