const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const webpush = require("web-push");

admin.initializeApp();
const db = admin.firestore();

const COLLECTION = "thndr_egx_pro";
const PORTFOLIO_DOC = "user_portfolio";
const BRIEFING_DOC = "daily_briefing";
const PUSH_DOC = "push_subscriptions";
const FEE_BUFFER = 4.0;

// VAPID Keys for iOS 16.4+ / iPhone 15 Pro Home Screen Web Push Notifications
const VAPID_PUBLIC_KEY = "BHvLqv69c0kQx6mjKkDnkVl88-JwvRSG2RewbDV3fE1DAEfWsn0ozEFZ4mpk5LqjV7YnYS9vPEiW2-Ika7kHtMs";
const VAPID_PRIVATE_KEY = "oX915WSHrP7YdrrPHnrS3g-dh4LSbm0oXQcRRdQAd0Q";

webpush.setVapidDetails(
  "mailto:michael@mitrixo.com",
  VAPID_PUBLIC_KEY,
  VAPID_PRIVATE_KEY
);

function getMarketsStatusCairo() {
  const now = new Date();
  const cairoStr = now.toLocaleString("en-US", { timeZone: "Africa/Cairo" });
  const cairoNow = new Date(cairoStr);
  const day = cairoNow.getDay(); // 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
  const hour = cairoNow.getHours();
  const min = cairoNow.getMinutes();
  const minsOfDay = hour * 60 + min;

  // 1. EGX Stock Exchange (Sun-Thu, Pre-Open 9:30-10:00, Main 10:00-14:30 Cairo)
  const isEgxTradingDay = day >= 0 && day <= 4;
  let egxState = "CLOSED";
  let egxBadge = "🔴 EGX CLOSED";
  let egxReason = "Outside trading hours (Sun–Thu 10:00 AM – 2:30 PM Cairo)";
  let minsUntilChange = 0;
  let nextEventLabel = "";

  if (isEgxTradingDay && minsOfDay >= 600 && minsOfDay < 870) {
    egxState = "OPEN";
    egxBadge = "🟢 EGX OPEN NOW";
    egxReason = "Live continuous trading on Thndr (10:00 AM – 2:30 PM Cairo)";
    minsUntilChange = 870 - minsOfDay;
    nextEventLabel = "Closes at 2:30 PM Cairo";
  } else if (isEgxTradingDay && minsOfDay >= 570 && minsOfDay < 600) {
    egxState = "PREOPEN";
    egxBadge = "🟡 EGX PRE-OPEN AUCTION";
    egxReason = "Pre-open discovery session — main trading starts at 10:00 AM Cairo";
    minsUntilChange = 600 - minsOfDay;
    nextEventLabel = "Opens at 10:00 AM Cairo";
  } else {
    egxState = "CLOSED";
    if (day === 5 || day === 6) {
      egxReason = "Weekend Holiday (Friday & Saturday) — EGX reopens Sunday 10:00 AM Cairo";
    } else if (minsOfDay < 570) {
      egxReason = "Morning Pre-Market — EGX opens today at 10:00 AM Cairo";
    } else {
      egxReason = "After-Hours (Closed at 2:30 PM) — Reopens next trading day at 10:00 AM Cairo";
    }
    // Calculate minutes until next 10:00 AM on a Sun-Thu
    let daysToAdd = 0;
    if (isEgxTradingDay && minsOfDay < 600) {
      daysToAdd = 0;
    } else if (day === 4 && minsOfDay >= 600) {
      daysToAdd = 3; // Thursday after 10am -> Sunday
    } else if (day === 5) {
      daysToAdd = 2; // Friday -> Sunday
    } else if (day === 6) {
      daysToAdd = 1; // Saturday -> Sunday
    } else {
      daysToAdd = 1; // Sun-Wed after 2:30pm -> Next day
    }
    minsUntilChange = daysToAdd * 1440 + (600 - minsOfDay);
    const nextDayName = daysToAdd === 0 ? "Today" : (day === 4 || day === 5 || day === 6 ? "Sunday" : "Tomorrow");
    nextEventLabel = `Opens ${nextDayName} at 10:00 AM Cairo`;
  }

  const d = Math.floor(minsUntilChange / 1440);
  const h = Math.floor((minsUntilChange % 1440) / 60);
  const m = minsUntilChange % 60;
  const countdownText = `${d > 0 ? d + "d " : ""}${h}h ${m}m`;

  // 2. US Stock Market on Thndr (Mon-Fri 16:30 - 23:00 Cairo, Pre-Market 11:00 - 16:30)
  const isUsDay = day >= 1 && day <= 5;
  let usState = "CLOSED";
  if (isUsDay && minsOfDay >= 990 && minsOfDay < 1380) usState = "OPEN NOW (4:30 PM – 11:00 PM)";
  else if (isUsDay && minsOfDay >= 660 && minsOfDay < 990) usState = "PRE-MARKET (Opens 4:30 PM)";
  else usState = "CLOSED (Mon–Fri 4:30 PM – 11:00 PM)";

  // 3. Global Gold Spot (Mon-Fri 24h)
  const isGoldSpotOpen = day >= 1 && day <= 5;

  return {
    cairoTimeFormatted: cairoNow.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" }),
    egxState,
    egxBadge,
    egxReason,
    countdownText,
    nextEventLabel,
    whatIsOpenNow: [
      {
        name: "🇪🇬 EGX Stocks (279 EGP Stocks)",
        open: egxState === "OPEN",
        status: egxState === "OPEN" ? `OPEN NOW (Closes in ${countdownText})` : `${egxState} (${nextEventLabel} • in ${countdownText})`,
        thndrTip: egxState === "OPEN"
          ? "You can place instant Market or Limit orders right now."
          : "Market Orders will be rejected! Use a 'Limit Order' on Thndr to queue for 10:00 AM open, or wait until open."
      },
      {
        name: "🪙 Thndr Gold & Savings Funds (AZ-Gold / Clouds)",
        open: true,
        status: "24/7 ORDER QUEUE OPEN",
        thndrTip: "You can place Buy orders for AZ-Gold or Thndr Savings Funds any time 24/7."
      },
      {
        name: "🌍 Global Gold Spot (24K / 21K EGP)",
        open: isGoldSpotOpen,
        status: isGoldSpotOpen ? "LIVE TRADING NOW (Mon–Fri 24h)" : "WEEKEND PAUSE (Reopens Mon 1:00 AM)",
        thndrTip: "Tracks live international gold ounce & USD/EGP."
      },
      {
        name: "🇺🇸 US Stocks on Thndr (NYSE / NASDAQ)",
        open: usState.startsWith("OPEN"),
        status: usState,
        thndrTip: "Main Wall Street session runs Mon–Fri 4:30 PM to 11:00 PM Cairo Time."
      }
    ]
  };
}

async function fetchMacroAndGold() {
  let usdEgp = 53.4;
  let goldOz = 4180.0;
  try {
    const res = await fetch("https://scanner.tradingview.com/global/scan", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        symbols: { tickers: ["FX_IDC:USDEGP", "TVC:GOLD"] },
        columns: ["name", "close", "change"]
      })
    });
    const data = await res.json();
    if (data && data.data) {
      for (const row of data.data) {
        if (row.s === "FX_IDC:USDEGP" && row.d[1]) usdEgp = Number(row.d[1]);
        if (row.s === "TVC:GOLD" && row.d[1]) goldOz = Number(row.d[1]);
      }
    }
  } catch (e) {}
  const gold24kEGP = Math.round((goldOz * usdEgp) / 31.1034768);
  const gold21kEGP = Math.round(gold24kEGP * 0.875);
  return {
    usdEgp: Number(usdEgp.toFixed(2)),
    goldOz: Number(goldOz.toFixed(2)),
    gold24kEGP,
    gold21kEGP
  };
}

async function scanWholeEGXMarket() {
  const body = {
    filter: [{ left: "currency", operation: "equal", right: "EGP" }],
    columns: [
      "name", "description", "close", "change", "RSI", "Recommend.All",
      "SMA20", "SMA50", "SMA200", "price_earnings_ttm", "dividends_yield_current",
      "Value.Traded", "MACD.macd", "MACD.signal", "BB.lower", "BB.upper", "sector"
    ],
    sort: { sortBy: "Value.Traded", sortOrder: "desc" },
    range: [0, 350]
  };

  const res = await fetch("https://scanner.tradingview.com/egypt/scan", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  const json = await res.json();
  const stocks = [];

  if (!json || !json.data) return stocks;

  for (const item of json.data) {
    const d = item.d;
    const ticker = String(d[0] || "");
    const fullName = String(d[1] || ticker);
    const price = Number(d[2] || 0);
    if (price <= 0) continue;

    const change = Number(d[3] || 0);
    const rsi = d[4] != null ? Number(d[4]) : 50;
    const rec = d[5] != null ? Number(d[5]) : 0;
    const sma20 = d[6] != null ? Number(d[6]) : price;
    const sma50 = d[7] != null ? Number(d[7]) : price;
    const sma200 = d[8] != null ? Number(d[8]) : price;
    const pe = d[9] != null ? Number(d[9]) : 0;
    const divYield = d[10] != null ? Number(d[10]) : 0;
    const valTraded = d[11] != null ? Number(d[11]) : 0;
    const macd = d[12] != null ? Number(d[12]) : 0;
    const macdSig = d[13] != null ? Number(d[13]) : 0;
    const bbLower = d[14] != null ? Number(d[14]) : price * 0.95;
    const bbUpper = d[15] != null ? Number(d[15]) : price * 1.05;
    const sector = String(d[16] || "General");

    let score = 50.0;
    const reasons = [];
    let plainWhy = "Steady market activity.";

    const isLiquid = valTraded >= 10000000 && price >= 1.5 && change > -4.0;
    if (valTraded >= 35000000) score += 8;
    else if (valTraded < 5000000) score -= 25;
    if (change <= -4.0) score -= 18;

    if (rsi <= 33) {
      score += 20;
      reasons.push(`Oversold Dip (RSI ${Math.round(rsi)})`);
      plainWhy = "Discounted dip on strong volume — high probability bounce setup.";
    } else if (rsi <= 48) {
      score += 14;
      reasons.push(`Good Entry (RSI ${Math.round(rsi)})`);
      plainWhy = "Healthy pullback offering a low-risk entry before the next leg up.";
    } else if (rsi <= 63) {
      score += 10;
      reasons.push(`Rising Trend (RSI ${Math.round(rsi)})`);
      plainWhy = "Buyers are steadily accumulating and pushing trend higher.";
    } else if (rsi >= 70) {
      score -= 25;
      reasons.push(`Overbought (RSI ${Math.round(rsi)})`);
      plainWhy = "Overheated short-term — wait for a pullback or take profits.";
    }

    if (price > sma200) {
      score += 10;
      if (price > sma20 && sma20 > sma50) {
        score += 8;
        reasons.push("Strong Uptrend");
      } else if (price < sma20) {
        score += 7;
        reasons.push("Pullback in Uptrend");
      }
    } else {
      score -= 12;
      if (price < sma50) score -= 6;
    }

    const macdBull = macd > macdSig;
    if (macdBull) {
      score += 8;
      reasons.push("MACD Bullish");
    } else {
      score -= 4;
    }

    if (price <= bbLower * 1.02) {
      score += 7;
      reasons.push("Near Lower Band");
    } else if (price >= bbUpper * 0.99 && rsi >= 65) {
      score -= 10;
    }

    score += rec * 14.0;
    if (pe > 0 && pe <= 10) {
      score += 7;
      reasons.push(`Low P/E ${pe.toFixed(1)}x`);
    }
    if (divYield >= 3.5) {
      score += 6;
      reasons.push(`Div ${divYield.toFixed(1)}%`);
    }

    score = Math.max(5, Math.min(99, Number(score.toFixed(1))));

    let signal = "WAIT / WATCH";
    if (score >= 74 && rsi < 66 && isLiquid) signal = "STRONG BUY";
    else if (score >= 65 && rsi < 65 && isLiquid) signal = "BUY";
    else if (rsi >= 70 || score <= 42) signal = "SELL / AVOID";

    stocks.push({
      ticker,
      fullName,
      price: Number(price.toFixed(2)),
      change: Number(change.toFixed(2)),
      rsi: Math.round(rsi),
      macdBull,
      sma50: Number(sma50.toFixed(2)),
      sma200: Number(sma200.toFixed(2)),
      pe: pe > 0 ? Number(pe.toFixed(1)) : null,
      divYield: divYield > 0 ? Number(divYield.toFixed(1)) : 0,
      valTradedM: Number((valTraded / 1e6).toFixed(1)),
      isLiquid,
      score,
      signal,
      targetPrice: Number((price * 1.12).toFixed(2)),
      stopLoss: Number((price * 0.95).toFixed(2)),
      sector,
      why: reasons.join(" • "),
      plainWhy
    });
  }

  stocks.sort((a, b) => b.score - a.score);
  return stocks;
}

const DEFAULT_NBE_CERTIFICATES = [
  {
    id: "1397980890284900037",
    name: "Platinum Certificate Step Down",
    principalEGP: 30000.0,
    ratePct: 19.0,
    monthlyPayoutEGP: 475.0,
    payoutDayOfMonth: 12,
    openedDate: "2024-08-11",
    maturityDate: "2028-08-12"
  },
  {
    id: "1397480890284900064",
    name: "Platinum Certificate (360K)",
    principalEGP: 360000.0,
    ratePct: 17.25,
    monthlyPayoutEGP: 5175.0,
    payoutDayOfMonth: 15,
    openedDate: "2026-06-14",
    maturityDate: "2029-06-15"
  },
  {
    id: "1397480890284900075",
    name: "Platinum Certificate (60K)",
    principalEGP: 60000.0,
    ratePct: 17.75,
    monthlyPayoutEGP: 887.5,
    payoutDayOfMonth: 5,
    openedDate: "2026-10-04",
    maturityDate: "2029-10-05"
  },
  {
    id: "1397480890284900086",
    name: "Platinum Certificate (10K)",
    principalEGP: 10000.0,
    ratePct: 17.75,
    monthlyPayoutEGP: 147.92,
    payoutDayOfMonth: 18,
    openedDate: "2026-10-15",
    maturityDate: "2029-10-18"
  }
];

async function getOrInitPortfolio() {
  const ref = db.collection(COLLECTION).doc(PORTFOLIO_DOC);
  const snap = await ref.get();
  if (snap.exists) {
    const data = snap.data();
    if (!data.goalEGP) data.goalEGP = 5000.0;
    if (!data.wealthGoalEGP) data.wealthGoalEGP = 500000.0;
    if (!data.weeklyDepositEGP) data.weeklyDepositEGP = 500.0;
    if (data.nbeFundBalanceEGP == null) data.nbeFundBalanceEGP = 0.0;
    if (!Array.isArray(data.nbeCertificates) || data.nbeCertificates.length === 0) {
      data.nbeCertificates = DEFAULT_NBE_CERTIFICATES;
    }
    if (!data.emailConfig) {
      data.emailConfig = { toEmail: "michael@mitrixo.com", enabled: true, sentAlerts: {} };
    }
    return data;
  }
  const initial = {
    cashEGP: 500.0,
    totalInvested: 500.0,
    goalEGP: 5000.0,
    wealthGoalEGP: 500000.0,
    weeklyDepositEGP: 500.0,
    nbeFundBalanceEGP: 0.0,
    nbeCertificates: DEFAULT_NBE_CERTIFICATES,
    holdings: [],
    emailConfig: {
      toEmail: "michael@mitrixo.com",
      enabled: true,
      sentAlerts: {}
    },
    updatedAt: new Date().toISOString()
  };
  await ref.set(initial);
  return initial;
}

async function sendCloudEmailAlert(toEmail, subject, plainText) {
  try {
    await fetch("https://formsubmit.co/ajax/" + encodeURIComponent(toEmail), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Referer": "https://thndr-egx-pro.web.app/",
        "Origin": "https://thndr-egx-pro.web.app"
      },
      body: JSON.stringify({
        _subject: subject,
        _template: "table",
        _captcha: "false",
        Source: "24/7 Thndr Cloud Worker",
        Alert: plainText,
        CairoTime: new Date().toLocaleString("en-US", { timeZone: "Africa/Cairo" })
      })
    });
  } catch (e) {}
}

async function sendWebPushToAllSubscribers(payloadObj) {
  try {
    const snap = await db.collection(COLLECTION).doc(PUSH_DOC).get();
    if (!snap.exists) return { sent: 0 };
    const data = snap.data() || {};
    const subs = Array.isArray(data.subscriptions) ? data.subscriptions : [];
    const validSubs = [];
    let sentCount = 0;

    for (const sub of subs) {
      try {
        await webpush.sendNotification(sub, JSON.stringify(payloadObj));
        validSubs.push(sub);
        sentCount++;
      } catch (err) {
        if (err.statusCode !== 404 && err.statusCode !== 410) {
          validSubs.push(sub);
        }
      }
    }

    if (validSubs.length !== subs.length) {
      await db.collection(COLLECTION).doc(PUSH_DOC).set({ subscriptions: validSubs }, { merge: true });
    }
    return { sent: sentCount };
  } catch (e) {
    return { sent: 0, error: e.message };
  }
}

async function runCloudAdvisorCycle(sendHourlyPush = false) {
  const [macro, stocks, portfolio] = await Promise.all([
    fetchMacroAndGold(),
    scanWholeEGXMarket(),
    getOrInitPortfolio()
  ]);

  const marketHours = getMarketsStatusCairo();
  const stockMap = {};
  stocks.forEach(s => { stockMap[s.ticker] = s; });

  const investableCash = Math.max(0, (portfolio.cashEGP || 500) - FEE_BUFFER);
  const liquidStocks = stocks.filter(s => s.isLiquid);

  const gainers = liquidStocks.filter(s => s.change > 0).length;
  const losers = liquidStocks.filter(s => s.change < 0).length;
  const breadthPct = liquidStocks.length > 0 ? Math.round((gainers / liquidStocks.length) * 100) : 50;
  let marketMood = "NEUTRAL / SELECTIVE";
  if (breadthPct >= 60) marketMood = "BULLISH (GREEN MARKET)";
  else if (breadthPct <= 38) marketMood = "CAUTIOUS / DIP-BUYING MARKET";

  const sectorScores = {};
  liquidStocks.slice(0, 25).forEach(s => {
    sectorScores[s.sector] = (sectorScores[s.sector] || 0) + 1;
  });
  const topSector = Object.entries(sectorScores).sort((a, b) => b[1] - a[1])[0]?.[0] || "Industrial & Finance";

  const topGrowthPick = liquidStocks.find(s => s.price <= Math.max(495, investableCash) && s.signal === "STRONG BUY") || liquidStocks[0];
  const topDipPick = liquidStocks.find(s => s.rsi <= 40 && s.price <= Math.max(495, investableCash) && s.ticker !== topGrowthPick?.ticker) || liquidStocks[1];
  const topDividendPick = [...liquidStocks].filter(s => s.divYield >= 2.0 && s.price <= Math.max(495, investableCash)).sort((a, b) => b.divYield - a.divYield)[0] || liquidStocks[2];

  let holdingsValue = 0;
  const todayKey = new Date().toLocaleDateString("en-CA", { timeZone: "Africa/Cairo" });
  const urgentSells = [];
  let portfolioUpdated = false;

  for (const h of (portfolio.holdings || [])) {
    const m = stockMap[h.ticker];
    const livePrice = m ? m.price : h.buyPrice;
    holdingsValue += h.shares * livePrice;
    const pnlPct = h.buyPrice > 0 ? ((livePrice - h.buyPrice) / h.buyPrice) * 100 : 0;

    let sellDirective = null;
    let sellReason = "";
    if (pnlPct >= 12.0) {
      sellDirective = "SELL NOW (TAKE PROFIT +12%)";
      sellReason = `Reached +${pnlPct.toFixed(1)}% profit (${livePrice} EGP). Lock in gains toward your ${portfolio.goalEGP} EGP challenge!`;
    } else if (m && m.rsi >= 70 && pnlPct >= 4.0) {
      sellDirective = "SELL NOW (OVERBOUGHT PEAK)";
      sellReason = `RSI hit ${m.rsi} (overbought) with +${pnlPct.toFixed(1)}% profit. Sell before pullback!`;
    } else if (m && !m.macdBull && m.rsi >= 65 && pnlPct >= 6.0) {
      sellDirective = "SELL NOW (MACD REVERSAL)";
      sellReason = `MACD turned bearish after +${pnlPct.toFixed(1)}% rally. Lock in profit!`;
    } else if (pnlPct <= -6.0 && m && livePrice < m.sma50) {
      sellDirective = "SELL NOW (STOP LOSS)";
      sellReason = `Dropped ${pnlPct.toFixed(1)}% below 50-day support (${m.sma50} EGP). Protect capital!`;
    }

    if (sellDirective) {
      urgentSells.push({ ticker: h.ticker, shares: h.shares, buyPrice: h.buyPrice, livePrice, pnlPct: Number(pnlPct.toFixed(2)), sellDirective, sellReason });
      const alertKey = `${h.ticker}_${todayKey}`;
      if (!portfolio.emailConfig?.sentAlerts?.[alertKey]) {
        if (!portfolio.emailConfig.sentAlerts) portfolio.emailConfig.sentAlerts = {};
        portfolio.emailConfig.sentAlerts[alertKey] = new Date().toISOString();
        portfolioUpdated = true;
        const toEmail = portfolio.emailConfig?.toEmail || "michael@mitrixo.com";
        await sendCloudEmailAlert(
          `🚨 THNDR CLOUD ALERT: SELL ${h.ticker} @ ${livePrice} EGP (${pnlPct >= 0 ? "+" : ""}${pnlPct.toFixed(1)}%)`,
          `${h.ticker}: ${sellDirective} | Shares: ${h.shares} | Buy: ${h.buyPrice} EGP -> Live: ${livePrice} EGP | ${sellReason}`
        );
        await sendWebPushToAllSubscribers({
          title: `🚨 SELL ${h.ticker} ON THNDR NOW!`,
          body: `${h.ticker} @ ${livePrice} EGP (${pnlPct >= 0 ? "+" : ""}${pnlPct.toFixed(1)}%): ${sellReason}`,
          tag: `sell-${h.ticker}`
        });
      }
    }
  }

  if (portfolioUpdated) {
    await db.collection(COLLECTION).doc(PORTFOLIO_DOC).set(portfolio, { merge: true });
  }

  const totalPortfolioVal = Number(((portfolio.cashEGP || 0) + holdingsValue).toFixed(2));
  const goalEGP = Number(portfolio.goalEGP || 5000);
  const remainingToGoal = Math.max(0, Number((goalEGP - totalPortfolioVal).toFixed(2)));
  const weeklyDep = Number(portfolio.weeklyDepositEGP || 500);
  let estWeeks = 0;
  let simVal = totalPortfolioVal;
  while (simVal < goalEGP && estWeeks < 260) {
    simVal = simVal * 1.022 + weeklyDep;
    estWeeks++;
  }

  const cairoTimestamp = new Date().toLocaleString("en-GB", {
    timeZone: "Africa/Cairo",
    weekday: "short",
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit"
  });

  const qtyTop = topGrowthPick ? Math.floor(investableCash / topGrowthPick.price) : 0;
  const marketPrefix = marketHours.egxState === "OPEN"
    ? `🟢 EGX OPEN (${marketHours.countdownText} left):`
    : `🔴 EGX CLOSED (${marketHours.nextEventLabel} in ${marketHours.countdownText}):`;

  const dailyAdviceHeadline = urgentSells.length > 0
    ? `${marketPrefix} 🚨 Sell ${urgentSells.map(u => u.ticker).join(", ")} on Thndr to lock in profits, then rotate into ${topGrowthPick?.ticker || "top picks"}!`
    : qtyTop >= 1
      ? marketHours.egxState === "OPEN"
        ? `${marketPrefix} Buy ${qtyTop} share(s) of ${topGrowthPick.ticker} @ ~${topGrowthPick.price} EGP now (Target Sell: ${topGrowthPick.targetPrice} EGP).`
        : `${marketPrefix} Top Pick is ${topGrowthPick.ticker} (${qtyTop} sh @ ${topGrowthPick.price} EGP). Do NOT use Market Order while closed—either place a Limit Order on Thndr to queue for 10:00 AM open, or buy AZ-Gold / Thndr Savings (Open 24/7)!`
      : `${marketPrefix} Capital deployed (${totalPortfolioVal} / ${goalEGP} EGP goal). Hold until +12% target or add your next ${weeklyDep} EGP weekly deposit.`;

  const briefing = {
    dateKey: todayKey,
    cairoTimestamp,
    marketHours,
    totalStocksScanned: stocks.length,
    marketMood,
    breadthPct,
    gainers,
    losers,
    topSector,
    macro,
    dailyAdviceHeadline,
    estWeeksToGoal: estWeeks,
    remainingToGoal,
    picks: {
      topGrowth: topGrowthPick || null,
      topDip: topDipPick || null,
      topDividend: topDividendPick || null
    },
    urgentSells,
    updatedAt: new Date().toISOString()
  };

  await db.collection(COLLECTION).doc(BRIEFING_DOC).set(briefing);

  if (sendHourlyPush) {
    const pushTitle = urgentSells.length > 0
      ? `🚨 SELL ${urgentSells.map(u => u.ticker).join(", ")} (${marketHours.egxBadge})`
      : `⚡ ${marketHours.egxBadge} • #1 Pick: ${topGrowthPick ? topGrowthPick.ticker : "EGX"}`;
    const pushBody = topGrowthPick
      ? `${marketHours.egxState === "OPEN" ? "Market OPEN Now!" : marketHours.nextEventLabel + " (in " + marketHours.countdownText + ")."} Top Buy: ${topGrowthPick.ticker} @ ${topGrowthPick.price} EGP -> Target ${topGrowthPick.targetPrice} EGP. 24K Gold: ${macro.gold24kEGP} EGP/g.`
      : dailyAdviceHeadline;
    await sendWebPushToAllSubscribers({
      title: pushTitle,
      body: pushBody,
      tag: "thndr-hourly-briefing",
      url: "/?from=hourly_push"
    });
  }

  return { portfolio, briefing };
}

// 1. Scheduled 24/7 Hourly Cloud Worker: Runs EVERY HOUR ("0 * * * *") in Cairo Time!
// Updates live market status, refreshes daily/hourly stock picks, checks SELL alerts, and sends Hourly Web Push to iPhone Home Screen App!
exports.thndrDailyAdvisorWorker = onSchedule(
  {
    schedule: "0 * * * *",
    timeZone: "Africa/Cairo",
    region: "us-central1",
    memory: "256MiB"
  },
  async () => {
    await runCloudAdvisorCycle(true);
  }
);

// 2. Live HTTP Cloud Worker Endpoint for iPhone 15 Pro App & Desktop BAT Script
exports.thndrLiveAdvisorApi = onRequest(
  {
    cors: true,
    region: "us-central1",
    memory: "256MiB"
  },
  async (req, res) => {
    try {
      if (req.method === "POST") {
        const body = typeof req.body === "string" ? JSON.parse(req.body) : (req.body || {});
        const current = await getOrInitPortfolio();

        if (body.action === "save_portfolio" && body.portfolio) {
          const updated = {
            ...current,
            cashEGP: Number(body.portfolio.cashEGP ?? current.cashEGP),
            totalInvested: Number(body.portfolio.totalInvested ?? current.totalInvested),
            goalEGP: Number(body.portfolio.goalEGP ?? current.goalEGP ?? 5000),
            wealthGoalEGP: Number(body.portfolio.wealthGoalEGP ?? current.wealthGoalEGP ?? 500000),
            weeklyDepositEGP: Number(body.portfolio.weeklyDepositEGP ?? current.weeklyDepositEGP ?? 500),
            nbeFundBalanceEGP: Number(body.portfolio.nbeFundBalanceEGP ?? current.nbeFundBalanceEGP ?? 0),
            nbeCertificates: Array.isArray(body.portfolio.nbeCertificates) ? body.portfolio.nbeCertificates : current.nbeCertificates,
            holdings: Array.isArray(body.portfolio.holdings) ? body.portfolio.holdings : current.holdings,
            emailConfig: body.portfolio.emailConfig || current.emailConfig,
            updatedAt: new Date().toISOString()
          };
          await db.collection(COLLECTION).doc(PORTFOLIO_DOC).set(updated);
          const result = await runCloudAdvisorCycle(false);
          return res.status(200).json({ ok: true, vapidPublicKey: VAPID_PUBLIC_KEY, ...result });
        }

        if (body.action === "subscribe_push" && body.subscription) {
          const ref = db.collection(COLLECTION).doc(PUSH_DOC);
          const snap = await ref.get();
          const subs = snap.exists && Array.isArray(snap.data().subscriptions) ? snap.data().subscriptions : [];
          const exists = subs.some(s => s.endpoint === body.subscription.endpoint);
          if (!exists) {
            subs.push(body.subscription);
            await ref.set({ subscriptions: subs, updatedAt: new Date().toISOString() }, { merge: true });
          }
          const mStatus = getMarketsStatusCairo();
          await webpush.sendNotification(
            body.subscription,
            JSON.stringify({
              title: "✅ Hourly iPhone Notifications Active!",
              body: `${mStatus.egxBadge} (${mStatus.nextEventLabel} in ${mStatus.countdownText}). You will receive hourly EGX updates & instant SELL alerts!`,
              tag: "thndr-welcome-push",
              url: "/"
            })
          );
          return res.status(200).json({ ok: true, subscribed: true });
        }

        if (body.action === "test_push") {
          const result = await runCloudAdvisorCycle(true);
          return res.status(200).json({ ok: true, pushed: true, ...result });
        }

        if (body.action === "refresh_briefing") {
          const result = await runCloudAdvisorCycle(false);
          return res.status(200).json({ ok: true, vapidPublicKey: VAPID_PUBLIC_KEY, ...result });
        }
      }

      const [portfolio, briefingSnap] = await Promise.all([
        getOrInitPortfolio(),
        db.collection(COLLECTION).doc(BRIEFING_DOC).get()
      ]);

      let briefing = briefingSnap.exists ? briefingSnap.data() : null;
      const ageMs = briefing && briefing.updatedAt ? (Date.now() - new Date(briefing.updatedAt).getTime()) : 999999999;

      if (!briefing || ageMs > 15 * 60 * 1000 || req.query.refresh === "1") {
        const fresh = await runCloudAdvisorCycle(false);
        return res.status(200).json({ ok: true, vapidPublicKey: VAPID_PUBLIC_KEY, ...fresh });
      }

      briefing.marketHours = getMarketsStatusCairo();
      return res.status(200).json({ ok: true, vapidPublicKey: VAPID_PUBLIC_KEY, portfolio, briefing });
    } catch (err) {
      return res.status(500).json({ ok: false, error: err.message });
    }
  }
);
