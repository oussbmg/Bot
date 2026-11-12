
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

void main() => runApp(const XgsApp());

enum Regime { unsafe, bull, bear, range, highVol, lowVol }

extension RegimeText on Regime {
  String get label => switch (this) {
        Regime.bull => 'STRONG BULL',
        Regime.bear => 'STRONG BEAR',
        Regime.range => 'RANGE',
        Regime.highVol => 'HIGH VOLATILITY',
        Regime.lowVol => 'LOW VOLATILITY',
        Regime.unsafe => 'UNSAFE / NO-TRADE',
      };
}

class Candle {
  final double open, high, low, close;
  Candle(this.open, this.high, this.low, this.close);
}

class Position {
  final int dir; // 1 buy, -1 sell
  final double lot, price;
  Position(this.dir, this.lot, this.price);
}

class Indicators {
  double emaF = 0, emaM = 0, emaS = 0, emaFPrev = 0, emaMPrev = 0;
  double rsi = 0, adx = 0, pdi = 0, mdi = 0, atr = 0, atrAvg = 0;
  double open1 = 0, close1 = 0, high1 = 0, low1 = 0, range1 = 0;
  double recentLow = 0, priorLow = 0, recentHigh = 0, priorHigh = 0;
}

class StrategySnapshot {
  final double price, spreadPoints, equity, balance, basketPnl;
  final Indicators ind;
  final Regime regime;
  final int score;
  final int direction;
  final String detail, riskStatus, lastEvent;
  final int entries;
  final double lots;

  StrategySnapshot({
    required this.price,
    required this.spreadPoints,
    required this.equity,
    required this.balance,
    required this.basketPnl,
    required this.ind,
    required this.regime,
    required this.score,
    required this.direction,
    required this.detail,
    required this.riskStatus,
    required this.lastEvent,
    required this.entries,
    required this.lots,
  });
}

/// Translation of the decision/risk logic in the supplied XAUGridScalper.mq4.
/// The Android build is PAPER TRADING ONLY: it never sends broker orders.
class XgsEngine {
  // Exact defaults from the MT4 file.
  static const emaFast = 20, emaMid = 50, emaSlow = 200;
  static const rsiPeriod = 14, adxPeriod = 14, atrPeriod = 14, atrAvgBars = 100;
  static const adxTrend = 22.0, adxRangeMax = 20.0;
  static const volHighMult = 1.8, volLowMult = 0.5, volExtremeMult = 3.0;
  static const slopeBars = 5, slopeMinAtr = 0.10, flatSlopeAtr = 0.15;
  static const minScore = 5;
  static const rsiBuyMin = 52.0, rsiSellMax = 48.0, rsiOverbought = 78.0;
  static const rangeRsiBuy = 35.0, rangeRsiSell = 65.0;
  static const rangeStretchAtr = 0.7, structBars = 10, maxExtensionAtr = 1.5;
  static const spikeMult = 2.5;
  static const gridAtrRange = 0.6, gridAtrTrend = 1.0, gridAtrHighVol = 1.5;
  static const gridInHighVol = false;
  static const maxPositions = 5, maxBasketLots = 0.05, minGridSpreadMult = 4.0;
  static const fixedLot = 0.01, maxLot = 0.02, riskPercent = 0.5, maxMarginUsage = 30.0;
  static const tpAtr = 0.7, tpMoney = 3.0, tpEquityPct = 0.15, minTpSpreadMult = 3.0;
  static const slMoney = 0.0, slEquityPct = 1.5, slAtr = 4.0;
  static const finalLevelAtr = 1.0, emergencySlAtr = 8.0;
  static const maxDailyLossPct = 2.0, maxDailyProfitPct = 2.0;
  static const maxEquityDdPct = 5.0, maxConsecLossBaskets = 3, maxTradesPerDay = 60;
  static const ecPausePct = 3.0, ecResumePct = 1.5, ecLookbackHours = 48;
  static const maxSpreadPts = 40.0, spreadAbnormalMult = 2.0;
  static const minSecBetweenTrades = 20, minBarsBetweenEntries = 1;
  static const maxTradesPerMinute = 3, maxTradesPerHour = 30;
  static const cooldownAfterCloseSec = 60;
  static const fridayNoEntryHour = 19, fridayCloseHour = 21;
  static const startingSpreadPoints = 20.0;

  final List<Candle> candles = [];
  final List<Position> positions = [];
  final List<DateTime> tradeTimes = [];
  final Random rng = Random(17);

  double balance = 1000;
  double equity = 1000;
  double peakEquity = 1000;
  double dayStartEquity = 1000;
  double price = 2650;
  double spreadPoints = startingSpreadPoints;
  double spreadAvg = startingSpreadPoints;
  int spreadSamples = 0;
  bool running = false;
  bool halted = false;
  bool dailyLossHit = false;
  bool dailyProfitHit = false;
  bool consecutivePause = false;
  bool equityCurvePause = false;
  int consecutiveLoss = 0;
  int tradesToday = 0;
  DateTime? lastEntryTime, lastCloseTime, lastCloseBar;
  DateTime currentTime = DateTime.now();
  String lastEvent = 'Waiting for demo feed…';
  Regime regime = Regime.unsafe;
  Indicators ind = Indicators();
  int score = 0, direction = 0;
  String detail = '';
  double basketPeak = 0;

  StrategySnapshot get snapshot => StrategySnapshot(
        price: price,
        spreadPoints: spreadPoints,
        equity: equity,
        balance: balance,
        basketPnl: basketPnl,
        ind: ind,
        regime: regime,
        score: score,
        direction: direction,
        detail: detail,
        riskStatus: riskStatus,
        lastEvent: lastEvent,
        entries: positions.length,
        lots: positions.fold(0.0, (s, p) => s + p.lot),
      );

  double get basketPnl {
    if (positions.isEmpty) return 0;
    // Demo XAU contract approximation: $100 per $1 price move per 1.00 lot.
    return positions.fold(0.0, (s, p) => s + (price - p.price) * p.dir * p.lot * 100);
  }

  String get riskStatus {
    if (halted) return 'HALTED';
    if (dailyLossHit) return 'DAILY LOSS LIMIT';
    if (dailyProfitHit) return 'DAILY TARGET';
    if (consecutivePause) return 'CONSECUTIVE LOSS PAUSE';
    if (equityCurvePause) return 'EQUITY CURVE PAUSE';
    return 'OK';
  }

  void reset() {
    candles.clear();
    positions.clear();
    tradeTimes.clear();
    balance = 1000;
    equity = 1000;
    peakEquity = 1000;
    dayStartEquity = 1000;
    price = 2650;
    spreadPoints = startingSpreadPoints;
    spreadAvg = startingSpreadPoints;
    spreadSamples = 0;
    running = false;
    halted = false;
    dailyLossHit = false;
    dailyProfitHit = false;
    consecutivePause = false;
    equityCurvePause = false;
    consecutiveLoss = 0;
    tradesToday = 0;
    lastEntryTime = lastCloseTime = lastCloseBar = null;
    currentTime = DateTime.now();
    lastEvent = 'Reset. Generating M1 history…';
    regime = Regime.unsafe;
    ind = Indicators();
    score = direction = 0;
    detail = '';
    basketPeak = 0;
    _seedHistory();
    _refresh();
  }

  void _seedHistory() {
    double p = price;
    for (int i = 0; i < 260; i++) {
      final wave = sin(i / 18.0) * 0.9 + sin(i / 7.0) * 0.25;
      final noise = (rng.nextDouble() - .5) * 0.55;
      final close = p + 0.08 + wave * 0.15 + noise;
      final high = max(p, close) + 0.35 + rng.nextDouble() * 0.4;
      final low = min(p, close) - 0.35 - rng.nextDouble() * 0.4;
      candles.add(Candle(p, high, low, close));
      p = close;
    }
    price = p;
  }

  void start() {
    if (candles.length < 205) _seedHistory();
    running = true;
    lastEvent = 'Paper engine RUNNING';
  }

  void stop() {
    running = false;
    lastEvent = 'Paper engine stopped';
  }

  void step() {
    _newSyntheticM1Bar();
    _refresh();
    if (!running) return;
    _updateRisk();
    regime = _classifyRegime();
    _manageBasket();
    if (positions.isNotEmpty) {
      _tryGridAdd();
    } else {
      _evaluateEntry();
    }
  }

  void _newSyntheticM1Bar() {
    currentTime = currentTime.add(const Duration(minutes: 1));
    final prev = candles.isEmpty ? price : candles.last.close;
    final trend = sin(candles.length / 31.0) * 0.20;
    final noise = (rng.nextDouble() - .5) * 1.0;
    final close = prev + trend + noise;
    final high = max(prev, close) + 0.25 + rng.nextDouble() * 0.45;
    final low = min(prev, close) - 0.25 - rng.nextDouble() * 0.45;
    candles.add(Candle(prev, high, low, close));
    if (candles.length > 600) candles.removeAt(0);
    price = close;
    spreadPoints = 14 + rng.nextDouble() * 18;
    spreadSamples++;
    if (spreadSamples <= 30) {
      spreadAvg = ((spreadAvg * (spreadSamples - 1)) + spreadPoints) / spreadSamples;
    } else {
      final a = 2 / (300 + 1);
      spreadAvg += (spreadPoints - spreadAvg) * a;
    }
  }

  double _ema(int period, int shift) {
    final end = candles.length - 1 - shift;
    if (end < period) return 0;
    final start = end - period * 3;
    double e = candles[max(0, start)].close;
    const alphaBase = 2.0;
    for (int i = max(0, start) + 1; i <= end; i++) {
      final alpha = alphaBase / (period + 1);
      e = candles[i].close * alpha + e * (1 - alpha);
    }
    return e;
  }

  double _atr(int shift) {
    final end = candles.length - 1 - shift;
    if (end < 1) return 0;
    final start = max(1, end - 80);
    double sum = 0;
    int n = 0;
    for (int i = start; i <= end; i++) {
      final c = candles[i], prev = candles[i - 1];
      final tr = max(c.high - c.low, max((c.high - prev.close).abs(), (c.low - prev.close).abs()));
      sum += tr; n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  double _rsi(int shift) {
    final end = candles.length - 1 - shift;
    if (end < rsiPeriod + 1) return 50;
    double gain = 0, loss = 0;
    for (int i = end - rsiPeriod + 1; i <= end; i++) {
      final d = candles[i].close - candles[i - 1].close;
      if (d >= 0) gain += d; else loss -= d;
    }
    final avgGain = gain / rsiPeriod, avgLoss = loss / rsiPeriod;
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  List<double> _adx(int shift) {
    final end = candles.length - 1 - shift;
    if (end < adxPeriod * 3) return [0, 0, 0];
    final start = end - 60;
    final trs = <double>[], plus = <double>[], minus = <double>[];
    for (int i = max(1, start); i <= end; i++) {
      final c = candles[i], p = candles[i - 1];
      final up = c.high - p.high, down = p.low - c.low;
      trs.add(max(c.high - c.low, max((c.high - p.close).abs(), (c.low - p.close).abs())));
      plus.add(up > down && up > 0 ? up : 0);
      minus.add(down > up && down > 0 ? down : 0);
    }
    double atr = trs.take(adxPeriod).fold(0.0, (a, b) => a + b) / adxPeriod;
    double pdi = 0, mdi = 0, adx = 0;
    final dxs = <double>[];
    for (int i = adxPeriod; i < trs.length; i++) {
      atr = ((atr * (adxPeriod - 1)) + trs[i]) / adxPeriod;
      final psm = plus.sublist(max(0, i - adxPeriod + 1), i + 1)
          .fold(0.0, (a, b) => a + b);
      final msm = minus.sublist(max(0, i - adxPeriod + 1), i + 1)
          .fold(0.0, (a, b) => a + b);
      pdi = atr == 0 ? 0 : 100 * (psm / adxPeriod) / atr;
      mdi = atr == 0 ? 0 : 100 * (msm / adxPeriod) / atr;
      final dx = (pdi + mdi) == 0 ? 0 : 100 * (pdi - mdi).abs() / (pdi + mdi);
      dxs.add(dx);
    }
    if (dxs.isNotEmpty) adx = dxs.length < adxPeriod
        ? dxs.fold(0.0, (a, b) => a + b) / dxs.length
        : dxs.sublist(dxs.length - adxPeriod).fold(0.0, (a, b) => a + b) / adxPeriod;
    return [adx, pdi, mdi];
  }

  void _refresh() {
    if (candles.length < 205) return;
    final a = _adx(1);
    ind = Indicators()
      ..emaF = _ema(emaFast, 1)
      ..emaFPrev = _ema(emaFast, 1 + slopeBars)
      ..emaM = _ema(emaMid, 1)
      ..emaMPrev = _ema(emaMid, 1 + slopeBars)
      ..emaS = _ema(emaSlow, 1)
      ..rsi = _rsi(1)
      ..adx = a[0]
      ..pdi = a[1]
      ..mdi = a[2]
      ..atr = _atr(1)
      ..atrAvg = List<double>.generate(atrAvgBars, (i) => _atr(i + 1))
          .fold(0.0, (x, y) => x + y) / atrAvgBars;
    final c = candles[candles.length - 2];
    ind.open1 = c.open; ind.close1 = c.close; ind.high1 = c.high; ind.low1 = c.low;
    ind.range1 = c.high - c.low;
    ind.recentLow = candles.sublist(candles.length - 4, candles.length - 1)
        .map((x) => x.low).reduce(min);
    ind.recentHigh = candles.sublist(candles.length - 4, candles.length - 1)
        .map((x) => x.high).reduce(max);
    final priorEnd = candles.length - 5;
    final priorStart = max(0, priorEnd - structBars + 1);
    ind.priorLow = candles.sublist(priorStart, priorEnd + 1).map((x) => x.low).reduce(min);
    ind.priorHigh = candles.sublist(priorStart, priorEnd + 1).map((x) => x.high).reduce(max);
  }

  Regime _classifyRegime() {
    if (ind.atr <= 0 || ind.atrAvg <= 0) return Regime.unsafe;
    if (spreadPoints > maxSpreadPts || _spreadAbnormal()) return Regime.unsafe;
    final ratio = ind.atr / ind.atrAvg;
    if (ratio > volHighMult) return Regime.highVol;
    if (ratio < volLowMult) return Regime.lowVol;
    final up = (ind.emaF - ind.emaFPrev) / ind.atr >= slopeMinAtr;
    final dn = (ind.emaFPrev - ind.emaF) / ind.atr >= slopeMinAtr;
    if (ind.adx >= adxTrend) {
      if (ind.close1 > ind.emaM && ind.emaM > ind.emaS &&
          ind.emaF > ind.emaM && ind.pdi > ind.mdi && up) return Regime.bull;
      if (ind.close1 < ind.emaM && ind.emaM < ind.emaS &&
          ind.emaF < ind.emaM && ind.mdi > ind.pdi && dn) return Regime.bear;
    }
    return Regime.range;
  }

  bool _spreadAbnormal() =>
      spreadSamples >= 30 && spreadAvg > 0 && spreadPoints > spreadAvg * spreadAbnormalMult;

  bool _volOk() {
    final ratio = ind.atr / ind.atrAvg;
    return ratio >= volLowMult && ratio <= volHighMult && ind.range1 <= ind.atr * spikeMult;
  }

  bool _spreadOk() => spreadPoints <= maxSpreadPts && !_spreadAbnormal();

  (int, String) _scoreTrend(int dir) {
    int s = 0; String d = '';
    if (dir > 0) {
      if (ind.close1 > ind.emaM && ind.emaM > ind.emaS && ind.emaF > ind.emaM) {s++; d += 'EMA ';}
      if ((ind.emaF - ind.emaFPrev) / ind.atr >= slopeMinAtr) {s++; d += 'SLOPE ';}
      if (ind.rsi >= rsiBuyMin && ind.rsi <= rsiOverbought) {s++; d += 'RSI ';}
      if (ind.adx >= adxTrend && ind.pdi > ind.mdi) {s++; d += 'ADX ';}
      if (ind.recentLow > ind.priorLow && (ind.close1 - ind.emaF) <= maxExtensionAtr * ind.atr) {s++; d += 'STRUCT ';}
    } else {
      if (ind.close1 < ind.emaM && ind.emaM < ind.emaS && ind.emaF < ind.emaM) {s++; d += 'EMA ';}
      if ((ind.emaFPrev - ind.emaF) / ind.atr >= slopeMinAtr) {s++; d += 'SLOPE ';}
      if (ind.rsi <= rsiSellMax && ind.rsi >= 100 - rsiOverbought) {s++; d += 'RSI ';}
      if (ind.adx >= adxTrend && ind.mdi > ind.pdi) {s++; d += 'ADX ';}
      if (ind.recentHigh < ind.priorHigh && (ind.emaF - ind.close1) <= maxExtensionAtr * ind.atr) {s++; d += 'STRUCT ';}
    }
    if (_volOk()) {s++; d += 'VOL ';}
    if (_spreadOk()) {s++; d += 'SPREAD ';}
    return (s, d);
  }

  (int, String) _scoreRange(int dir) {
    int s = 0; String d = '';
    if (dir > 0) {
      if (ind.rsi <= rangeRsiBuy) {s++; d += 'RSI ';}
      if ((ind.emaF - ind.close1) >= rangeStretchAtr * ind.atr) {s++; d += 'STRETCH ';}
      if (ind.close1 > ind.open1) {s++; d += 'REVERSAL ';}
    } else {
      if (ind.rsi >= rangeRsiSell) {s++; d += 'RSI ';}
      if ((ind.close1 - ind.emaF) >= rangeStretchAtr * ind.atr) {s++; d += 'STRETCH ';}
      if (ind.close1 < ind.open1) {s++; d += 'REVERSAL ';}
    }
    if (ind.adx < adxRangeMax) {s++; d += 'ADXLOW ';}
    if ((ind.emaM - ind.emaMPrev).abs() / ind.atr <= flatSlopeAtr) {s++; d += 'FLAT ';}
    if (_volOk()) {s++; d += 'VOL ';}
    if (_spreadOk()) {s++; d += 'SPREAD ';}
    return (s, d);
  }

  bool _entriesAllowed(bool grid) {
    if (halted || dailyLossHit || dailyProfitHit || consecutivePause || equityCurvePause) return false;
    if (tradesToday >= maxTradesPerDay) return false;
    if (spreadPoints > maxSpreadPts || _spreadAbnormal()) return false;
    final sec = lastEntryTime == null ? 999999 : currentTime.difference(lastEntryTime!).inSeconds;
    if (sec < minSecBetweenTrades) return false;
    final min = currentTime.difference(currentTime.subtract(const Duration(minutes: 1))).inSeconds;
    if (tradeTimes.where((t) => currentTime.difference(t).inSeconds < 60).length >= maxTradesPerMinute) return false;
    if (tradeTimes.where((t) => currentTime.difference(t).inSeconds < 3600).length >= maxTradesPerHour) return false;
    if (!grid && lastCloseTime != null &&
        currentTime.difference(lastCloseTime!).inSeconds < cooldownAfterCloseSec) return false;
    return true;
  }

  double _computeLot() => fixedLot;

  void _evaluateEntry() {
    if (positions.isNotEmpty || !_entriesAllowed(false)) return;
    if (regime == Regime.unsafe || regime == Regime.highVol || regime == Regime.lowVol) {
      lastEvent = 'ENTRY REJECTED: ${regime.label}'; return;
    }
    final int dir;
    final int s;
    final String d;
    if (regime == Regime.bull) {
      dir = 1; final r = _scoreTrend(1); s = r.$1; d = r.$2;
    } else if (regime == Regime.bear) {
      dir = -1; final r = _scoreTrend(-1); s = r.$1; d = r.$2;
    } else {
      final b = _scoreRange(1), sell = _scoreRange(-1);
      if (b.$1 >= sell.$1) {dir = 1; s = b.$1; d = b.$2;}
      else {dir = -1; s = sell.$1; d = sell.$2;}
    }
    direction = dir; score = s; detail = d;
    if (s < minScore) {
      lastEvent = 'ENTRY REJECTED: score $s/7 < $minScore [$d]'; return;
    }
    final lot = _computeLot();
    if (positions.fold(0.0, (x, p) => x + p.lot) + lot > maxBasketLots) {
      lastEvent = 'ENTRY REJECTED: max basket lots'; return;
    }
    _open(dir, lot, 'ENTRY ${regime.label} score=$s/7 [$d]');
  }

  void _open(int dir, double lot, String reason) {
    positions.add(Position(dir, lot, price + (dir > 0 ? spreadPoints * 0.01 : -spreadPoints * 0.01)));
    tradesToday++;
    lastEntryTime = currentTime;
    tradeTimes.add(currentTime);
    lastEvent = '$reason | ${dir > 0 ? "BUY" : "SELL"} $lot @ ${price.toStringAsFixed(2)}';
    basketPeak = max(basketPeak, basketPnl);
  }

  void _tryGridAdd() {
    if (positions.isEmpty || positions.length >= maxPositions) return;
    double mult = 0;
    if (regime == Regime.range) mult = gridAtrRange;
    else if (regime == Regime.bull && positions.first.dir > 0) mult = gridAtrTrend;
    else if (regime == Regime.bear && positions.first.dir < 0) mult = gridAtrTrend;
    else if (regime == Regime.highVol && gridInHighVol) mult = gridAtrHighVol;
    if (mult <= 0) return;
    final dist = max(ind.atr * mult, spreadPoints * 0.01 * minGridSpreadMult);
    final dir = positions.first.dir;
    final trigger = dir > 0 ? price <= positions.last.price - dist : price >= positions.last.price + dist;
    if (!trigger || !_entriesAllowed(true)) return;
    final lot = _computeLot();
    if (positions.fold(0.0, (x, p) => x + p.lot) + lot > maxBasketLots) return;
    _open(dir, lot, 'GRID level ${positions.length + 1} dist=${dist.toStringAsFixed(2)} mult=$mult');
  }

  void _manageBasket() {
    if (positions.isEmpty) return;
    final pnl = basketPnl;
    basketPeak = max(basketPeak, pnl);
    final vpu = 100.0;
    final spreadPx = spreadPoints * 0.01;
    final atr0 = ind.atr;
    final tp = max(atr0 * tpAtr, spreadPx * minTpSpreadMult) *
        positions.fold(0.0, (s, p) => s + p.lot) * vpu;
    double sl = double.infinity;
    String slWhy = '';
    if (slMoney > 0) {sl = slMoney; slWhy = 'MONEY';}
    final eqSl = dayStartEquity * slEquityPct / 100;
    if (eqSl < sl) {sl = eqSl; slWhy = 'EQUITY%';}
    final atrSl = atr0 * slAtr * positions.fold(0.0, (s, p) => s + p.lot) * vpu;
    if (atrSl < sl) {sl = atrSl; slWhy = 'ATR';}

    if (pnl >= tp) { _close('BASKET TP ${pnl.toStringAsFixed(2)} >= ${tp.toStringAsFixed(2)}'); return; }
    if (pnl <= -sl) { _close('BASKET SL ($slWhy) ${pnl.toStringAsFixed(2)}'); return; }

    if (positions.length >= maxPositions) {
      final last = positions.last.price;
      final adverse = positions.first.dir > 0 ? last - price : price - last;
      if (adverse >= finalLevelAtr * atr0) {
        _close('MAX GRID LEVELS STOP'); return;
      }
    }

    if (currentTime.weekday == DateTime.friday && currentTime.hour >= fridayCloseHour) {
      _close('FRIDAY CLOSE');
    }
  }

  void _close(String reason) {
    final pnl = basketPnl;
    balance += pnl;
    equity = balance;
    if (pnl < 0) {
      consecutiveLoss++;
      if (consecutiveLoss >= maxConsecLossBaskets) consecutivePause = true;
    } else {
      consecutiveLoss = 0;
    }
    lastCloseTime = currentTime;
    lastCloseBar = currentTime;
    lastEvent = 'BASKET CLOSED ${pnl >= 0 ? "+" : ""}${pnl.toStringAsFixed(2)} | $reason';
    positions.clear();
    basketPeak = 0;
  }

  void _updateRisk() {
    equity = balance + basketPnl;
    peakEquity = max(peakEquity, equity);
    final dd = peakEquity <= 0 ? 0 : (peakEquity - equity) / peakEquity * 100;
    final daily = dayStartEquity <= 0 ? 0 : (equity - dayStartEquity) / dayStartEquity * 100;
    if (daily <= -maxDailyLossPct) dailyLossHit = true;
    if (daily >= maxDailyProfitPct) dailyProfitHit = true;
    if (dd >= maxEquityDdPct) {
      halted = true;
      if (positions.isNotEmpty) _close('MAX EQUITY DRAWDOWN');
    }
    if (equityCurvePause) {
      if (dd <= ecResumePct) equityCurvePause = false;
    } else if (dd >= ecPausePct) {
      equityCurvePause = true;
    }
  }
}

class XgsApp extends StatelessWidget {
  const XgsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'XAU Grid Scalper Demo',
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: const DemoPage(),
      );
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});
  @override State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final XgsEngine engine = XgsEngine();
  Timer? timer;

  @override
  void initState() {
    super.initState();
    engine.reset();
  }

  @override
  void dispose() { timer?.cancel(); super.dispose(); }

  void toggle() {
    setState(() {
      if (engine.running) {
        engine.stop(); timer?.cancel();
      } else {
        engine.start();
        timer = Timer.periodic(const Duration(milliseconds: 900), (_) => setState(() => engine.step()));
      }
    });
  }

  void step() => setState(() => engine.step());

  @override
  Widget build(BuildContext context) {
    final s = engine.snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('XAUGridScalper • Android Demo')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('XAUUSD  M1', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('\$${s.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              Text('Spread: ${s.spreadPoints.toStringAsFixed(1)} pts • Demo feed'),
            ]),
          )),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: toggle, icon: Icon(engine.running ? Icons.stop : Icons.play_arrow), label: Text(engine.running ? 'STOP' : 'START'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: step, icon: const Icon(Icons.skip_next), label: const Text('1 M1'))),
            const SizedBox(width: 8),
            IconButton(onPressed: () => setState(() => engine.reset()), icon: const Icon(Icons.restart_alt)),
          ]),
          const SizedBox(height: 8),
          _infoCard('STRATEGY STATE', [
            _row('Regime', s.regime.label),
            _row('Score', '${s.score}/7'),
            _row('Direction', s.direction > 0 ? 'BUY' : s.direction < 0 ? 'SELL' : '-'),
            _row('EMA', '${s.ind.emaF.toStringAsFixed(2)} / ${s.ind.emaM.toStringAsFixed(2)} / ${s.ind.emaS.toStringAsFixed(2)}'),
            _row('RSI / ADX', '${s.ind.rsi.toStringAsFixed(1)} / ${s.ind.adx.toStringAsFixed(1)}'),
            _row('ATR / ATR avg', '${s.ind.atr.toStringAsFixed(3)} / ${s.ind.atrAvg.toStringAsFixed(3)}'),
            _row('Score details', s.detail.isEmpty ? '-' : s.detail),
          ]),
          _infoCard('PAPER ACCOUNT', [
            _row('Balance', '\$${s.balance.toStringAsFixed(2)}'),
            _row('Equity', '\$${s.equity.toStringAsFixed(2)}'),
            _row('Basket P/L', '${s.basketPnl >= 0 ? "+" : ""}\$${s.basketPnl.toStringAsFixed(2)}'),
            _row('Positions', '${s.entries} / ${XgsEngine.maxPositions}'),
            _row('Lots', '${s.lots.toStringAsFixed(2)} / ${XgsEngine.maxBasketLots.toStringAsFixed(2)}'),
            _row('Risk', s.riskStatus),
          ]),
          _infoCard('ACTIVITY', [_row('Last event', s.lastEvent)]),
          _infoCard('MT4 PARAMETERS PRESERVED', [
            _row('EMA', '20 / 50 / 200'),
            _row('RSI / ADX / ATR', '14 / 14 / 14'),
            _row('Min score', '5 / 7'),
            _row('Max positions', '5'),
            _row('Fixed lot', '0.01'),
            _row('Max basket lots', '0.05'),
            _row('Grid ATR', '0.6 range / 1.0 trend / 1.5 high-vol'),
            _row('Max spread', '40 points'),
            _row('Daily loss / equity DD', '2% / 5%'),
          ]),
          const SizedBox(height: 12),
          const Text(
            'PAPER TRADING ONLY. This build does not connect to Exness and cannot place real orders.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            ...children,
          ]),
        ),
      );

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(a, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(b)),
        ]),
      );
}
