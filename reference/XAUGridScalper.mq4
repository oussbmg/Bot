//+------------------------------------------------------------------+
//| XAUGridScalper.mq4                                               |
//| MT4 conversion of the supplied XAUGridScalper.mq5               |
//| Adaptive, risk-capped basket/grid scalper for XAUUSD (M1)        |
//| NO martingale. NO unlimited grid. NO profit guarantee.          |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "MT4 conversion of XAUGridScalper.mq5."
#property description "Fixed/risk lots, directional basket, virtual TP/SL, emergency SL."
#property description "Test thoroughly on demo / Strategy Tester before any live use."

enum ENUM_LOT_MODE { LOT_FIXED=0, LOT_RISK=1 };
enum ENUM_TP_MODE  { TP_ATR=0, TP_MONEY=1, TP_EQUITY_PCT=2 };
enum ENUM_REGIME   { REG_UNSAFE=0, REG_BULL=1, REG_BEAR=2, REG_RANGE=3, REG_HIGHVOL=4, REG_LOWVOL=5 };

input long   InpMagic=20260612;
input string InpComment="XGS";
input int    InpSlippage=30;
input int    InpMaxRetries=3;
input bool   InpVerbose=true;
input bool   InpLogCSV=false;
input bool   InpDashboard=true;

input int    InpEmaFast=20;
input int    InpEmaMid=50;
input int    InpEmaSlow=200;
input int    InpRSIPeriod=14;
input int    InpADXPeriod=14;
input int    InpATRPeriod=14;
input int    InpATRAvgBars=100;

input double InpADXTrend=22.0;
input double InpADXRangeMax=20.0;
input double InpVolHighMult=1.8;
input double InpVolLowMult=0.5;
input double InpVolExtremeMult=3.0;
input bool   InpCloseOnExtremeVol=false;
input int    InpSlopeBars=5;
input double InpSlopeMinATR=0.10;
input double InpFlatSlopeATR=0.15;

input int    InpMinScore=5;
input double InpRSIBuyMin=52.0;
input double InpRSISellMax=48.0;
input double InpRSIOverbought=78.0;
input double InpRangeRSIBuy=35.0;
input double InpRangeRSISell=65.0;
input double InpRangeStretchATR=0.7;
input int    InpStructBars=10;
input double InpMaxExtensionATR=1.5;
input double InpSpikeMult=2.5;

input double InpGridATR_Range=0.6;
input double InpGridATR_Trend=1.0;
input double InpGridATR_HighVol=1.5;
input bool   InpGridInHighVol=false;
input int    InpMaxPositions=5;
input double InpMaxBasketLots=0.05;
input double InpMinGridSpreadMult=4.0;

input ENUM_LOT_MODE InpLotMode=LOT_FIXED;
input double InpFixedLot=0.01;
input double InpMaxLot=0.02;
input double InpRiskPercent=0.5;
input double InpMaxMarginUsage=30.0;

input ENUM_TP_MODE InpTPMode=TP_ATR;
input double InpTP_ATR=0.7;
input double InpTP_Money=3.0;
input double InpTP_EquityPct=0.15;
input double InpMinTPSpreadMult=3.0;

input double InpSL_Money=0.0;
input double InpSL_EquityPct=1.5;
input double InpSL_ATR=4.0;
input double InpFinalLevelATR=1.0;
input bool   InpUseEmergencySL=true;
input double InpEmergencySL_ATR=8.0;

input bool   InpUseTrail=false;
input double InpTrailStartPctTP=60.0;
input double InpTrailGiveBackPct=35.0;
input double InpMinLockMoney=0.5;

input double InpMaxDailyLossPct=2.0;
input double InpMaxDailyProfitPct=2.0;
input bool   InpCloseBasketOnDailyLoss=false;
input double InpMaxEquityDDPct=5.0;
input bool   InpManualReset=true;
input int    InpMaxConsecLossBaskets=3;
input int    InpMaxTradesPerDay=60;

input bool   InpUseEquityCurve=true;
input double InpECPausePct=3.0;
input double InpECResumePct=1.5;
input int    InpECLookbackHours=48;

input int    InpMaxSpreadPts=40;
input double InpSpreadAbnormalMult=2.0;
input int    InpSpreadAvgTicks=300;

input int    InpMinSecBetweenTrades=20;
input int    InpMinBarsBetweenEntries=1;
input int    InpMaxTradesPerMinute=3;
input int    InpMaxTradesPerHour=30;
input int    InpCooldownAfterCloseSec=60;
input bool   InpNewBarAfterClose=true;

input bool   InpUseSessions=true;
input bool   InpLondon=false;
input int    InpLondonStart=9;
input int    InpLondonEnd=17;
input bool   InpNewYork=false;
input int    InpNewYorkStart=15;
input int    InpNewYorkEnd=23;
input bool   InpOverlap=true;
input int    InpOverlapStart=15;
input int    InpOverlapEnd=19;
input int    InpFridayNoEntryHour=19;
input int    InpFridayCloseHour=21;

input bool   InpUseNews=false;
input string InpNewsList="";
input bool   InpCloseBasketInNews=false;

input bool   InpUsePending=false;
input double InpPendingOffsetATR=0.3;
input int    InpPendingExpirySec=120;
input double InpPendingMaxDistATR=1.0;

input int    InpMinTradesOpt=100;

struct SInd {
   bool valid;
   double emaF,emaM,emaS,emaFPrev,emaMPrev;
   double rsi,adx,pdi,mdi,atr,atrAvg;
   double open1,close1,high1,low1,range1;
   double recentLow,priorLow,recentHigh,priorHigh;
   datetime barTime;
};
struct SBasket {
   bool active;
   int dir,id,entries,count;
   double vol,avg,profit,firstPrice,lastPrice,atrOpen,equityOpen;
   double peakProfit,minProfit;
   datetime openTime;
};
struct SStats {
   int baskets,wins,losses,maxEntries,consecWins,consecLosses,maxConsecWins,maxConsecLosses;
   double grossProfit,grossLoss,largestWin,largestLoss,totalDurationSec,totalEntries,maxFloatDD;
};

SInd g_ind;
SBasket g_b;
SStats g_st;
ENUM_REGIME g_regime=REG_UNSAFE;

double g_point,g_tickSize,g_tickValue,g_volMin,g_volMax,g_volStep;
int g_digits,g_stopsLevel,g_freezeLevel;
bool g_ready=false,g_tester=false,g_visual=false,g_quiet=false;
double g_bid=0,g_ask=0,g_spreadPts=0,g_spreadAvg=0;
int g_spreadSamples=0;

bool g_newBar=false;
datetime g_lastBarTime=0;
int g_dayKey=0;
double g_dayStartEq=0,g_peakEq=0,g_dailyPct=0,g_ddPct=0;
bool g_dailyLossHit=false,g_dailyProfitHit=false,g_consecPause=false;
bool g_halted=false;
string g_haltReason="";
int g_consecLoss=0,g_tradesToday=0;
bool g_ecPaused=false;
double g_ecPeak=0;
double g_ecBucket[];
long g_ecHour[];
datetime g_lastEcCalc=0;

datetime g_tradeTimes[];
datetime g_lastEntryTime=0,g_lastCloseTime=0,g_lastCloseBar=0,g_lastEntryBar=0;
string g_forceClose="";
string g_lastTradeText="-";
string g_lastRejectText="";
datetime g_lastRejectTime=0;
string g_csvName="";
int g_basketSeq=0;
double g_tpMoneyCache=0,g_slMoneyCache=0;
datetime g_nbStart[],g_nbEnd[];

#define PFX "XGS_"
#define RET_DONE 0
#define RET_REQUOTE 1
#define RET_TRADE_ERROR 2

void Log(string s){ if(!g_quiet) Print(s); }
string RegimeName(ENUM_REGIME r){
   if(r==REG_BULL)return "STRONG BULL";
   if(r==REG_BEAR)return "STRONG BEAR";
   if(r==REG_RANGE)return "RANGE";
   if(r==REG_HIGHVOL)return "HIGH VOLATILITY";
   if(r==REG_LOWVOL)return "LOW VOLATILITY";
   return "UNSAFE / NO-TRADE";
}
int DayKey(datetime t){
   MqlDateTime d; TimeToStruct(t,d);
   return d.year*10000+d.mon*100+d.day;
}
double NormVol(double v){
   double step=(g_volStep>0?g_volStep:0.01);
   double x=MathFloor(v/step+1e-9)*step;
   x=NormalizeDouble(x,2);
   if(x>g_volMax)x=g_volMax;
   if(x<g_volMin-1e-12)return 0;
   return x;
}
double NormPrice(double p){ return NormalizeDouble(p,g_digits); }
double MoneyPerPriceUnitPerLot(){
   if(g_tickSize<=0)return 0;
   return g_tickValue/g_tickSize;
}
void Reject(string why){
   if(g_quiet||!InpVerbose)return;
   datetime now=TimeCurrent();
   if(why==g_lastRejectText && now-g_lastRejectTime<30)return;
   g_lastRejectText=why;g_lastRejectTime=now;Print(why);
}
string DirText(int dir){
   if(dir>0)return "BUY";
   if(dir<0)return "SELL";
   return "-";
}
string BasketDirText(){
   if(!g_b.active)return "none";
   return DirText(g_b.dir);
}
string PendingDirText(int dir){
   if(dir>0)return "BUY STOP";
   return "SELL STOP";
}
string PendingShortText(int dir){
   if(dir>0)return "BUYSTOP";
   return "SELLSTOP";
}
string TradingStatusText(bool on,bool sess,string why){
   string a="OFF";
   if(on)a="ON";
   if(sess)return a+" (session OK)";
   return a+" ("+why+")";
}

string GVName(string key){
   return "XGS_"+IntegerToString(AccountNumber())+"_"+IntegerToString((int)InpMagic)+"_"+Symbol()+"_"+key;
}
void GVSet(string key,double v){ if(!g_tester) GlobalVariableSet(GVName(key),v); }
double GVGet(string key,double def){
   if(g_tester)return def;
   string n=GVName(key);
   if(GlobalVariableCheck(n))return GlobalVariableGet(n);
   return def;
}

void ParseNews(){
   ArrayResize(g_nbStart,0);ArrayResize(g_nbEnd,0);
   if(!InpUseNews||StringLen(InpNewsList)<10)return;
   string items[];int n=StringSplit(InpNewsList,';',items);
   for(int i=0;i<n;i++){
      string it=items[i];StringTrimLeft(it);StringTrimRight(it);
      int sp=StringFind(it," ");if(sp<0)continue;
      string date=StringSubstr(it,0,sp),rng=StringSubstr(it,sp+1),tt[];
      if(StringSplit(rng,'-',tt)!=2)continue;
      datetime a=StringToTime(date+" "+tt[0]),b=StringToTime(date+" "+tt[1]);
      if(a==0||b<=a)continue;
      int k=ArraySize(g_nbStart);ArrayResize(g_nbStart,k+1);ArrayResize(g_nbEnd,k+1);
      g_nbStart[k]=a;g_nbEnd[k]=b;
   }
}
bool InNewsBlackout(){
   if(!InpUseNews)return false;
   datetime now=TimeCurrent();
   for(int i=0;i<ArraySize(g_nbStart);i++)if(now>=g_nbStart[i]&&now<=g_nbEnd[i])return true;
   return false;
}
bool InHourWindow(int h,int s,int e){
   if(s==e)return true;
   if(s<e)return h>=s&&h<e;
   return h>=s||h<e;
}
bool SessionOK(string &why){
   MqlDateTime d;TimeToStruct(TimeCurrent(),d);
   if(d.day_of_week==0||d.day_of_week==6){why="weekend";return false;}
   if(d.day_of_week==5&&InpFridayNoEntryHour>0&&d.hour>=InpFridayNoEntryHour){why="Friday no-entry window";return false;}
   if(!InpUseSessions)return true;
   bool ok=false;
   if(InpLondon&&InHourWindow(d.hour,InpLondonStart,InpLondonEnd))ok=true;
   if(InpNewYork&&InHourWindow(d.hour,InpNewYorkStart,InpNewYorkEnd))ok=true;
   if(InpOverlap&&InHourWindow(d.hour,InpOverlapStart,InpOverlapEnd))ok=true;
   if(!ok)why="outside enabled sessions (server hour "+IntegerToString(d.hour)+")";
   return ok;
}
bool RefreshMarket(){
   RefreshRates();g_bid=Bid;g_ask=Ask;
   if(g_bid<=0||g_ask<=0||g_ask<g_bid)return false;
   g_spreadPts=(g_ask-g_bid)/g_point;g_spreadSamples++;
   if(g_spreadSamples<=30)g_spreadAvg=(g_spreadAvg*(g_spreadSamples-1)+g_spreadPts)/g_spreadSamples;
   else{
      double a=2.0/(InpSpreadAvgTicks+1.0);
      if(g_spreadPts<=g_spreadAvg*InpSpreadAbnormalMult)g_spreadAvg+=(g_spreadPts-g_spreadAvg)*a;
      else g_spreadAvg+=(g_spreadPts-g_spreadAvg)*a*0.05;
   }
   return true;
}
bool SpreadAbnormal(){return g_spreadSamples>=30&&g_spreadAvg>0&&g_spreadPts>g_spreadAvg*InpSpreadAbnormalMult;}

double EMA(int period,int shift){return iMA(NULL,0,period,0,MODE_EMA,PRICE_CLOSE,shift);}
double ATR(int shift){return iATR(NULL,0,InpATRPeriod,shift);}
double RSI(int shift){return iRSI(NULL,0,InpRSIPeriod,PRICE_CLOSE,shift);}
double ADX(int mode,int shift){return iADX(NULL,0,InpADXPeriod,PRICE_CLOSE,mode,shift);}

bool RefreshIndicators(){
   g_ind.valid=false;
   int need=InpSlopeBars+3;
   if(Bars<MathMax(InpATRAvgBars+5,InpStructBars+8))return false;
   g_ind.emaF=EMA(InpEmaFast,1);g_ind.emaFPrev=EMA(InpEmaFast,1+InpSlopeBars);
   g_ind.emaM=EMA(InpEmaMid,1);g_ind.emaMPrev=EMA(InpEmaMid,1+InpSlopeBars);
   g_ind.emaS=EMA(InpEmaSlow,1);
   g_ind.rsi=RSI(1);g_ind.adx=ADX(MODE_MAIN,1);g_ind.pdi=ADX(MODE_PLUSDI,1);g_ind.mdi=ADX(MODE_MINUSDI,1);
   g_ind.atr=ATR(1);
   double s=0;
   for(int i=1;i<=InpATRAvgBars;i++)s+=ATR(i);
   g_ind.atrAvg=s/InpATRAvgBars;
   g_ind.open1=iOpen(NULL,0,1);g_ind.close1=iClose(NULL,0,1);g_ind.high1=iHigh(NULL,0,1);g_ind.low1=iLow(NULL,0,1);
   g_ind.range1=g_ind.high1-g_ind.low1;g_ind.barTime=iTime(NULL,0,0);
   g_ind.recentLow=g_ind.low1;g_ind.recentHigh=g_ind.high1;
   for(int i=1;i<=3;i++){g_ind.recentLow=MathMin(g_ind.recentLow,iLow(NULL,0,i));g_ind.recentHigh=MathMax(g_ind.recentHigh,iHigh(NULL,0,i));}
   g_ind.priorLow=iLow(NULL,0,4);g_ind.priorHigh=iHigh(NULL,0,4);
   int maxI=MathMin(3+InpStructBars,Bars-1);
   for(int i=4;i<=maxI;i++){g_ind.priorLow=MathMin(g_ind.priorLow,iLow(NULL,0,i));g_ind.priorHigh=MathMax(g_ind.priorHigh,iHigh(NULL,0,i));}
   if(g_ind.atr<=0||g_ind.atrAvg<=0)return false;
   g_ind.valid=true;return true;
}
ENUM_REGIME ClassifyRegime(){
   if(!g_ind.valid)return REG_UNSAFE;
   if(g_spreadPts>InpMaxSpreadPts||SpreadAbnormal())return REG_UNSAFE;
   double ratio=g_ind.atr/g_ind.atrAvg;
   if(ratio>InpVolHighMult)return REG_HIGHVOL;
   if(ratio<InpVolLowMult)return REG_LOWVOL;
   bool up=(g_ind.emaF-g_ind.emaFPrev)/g_ind.atr>=InpSlopeMinATR;
   bool dn=(g_ind.emaFPrev-g_ind.emaF)/g_ind.atr>=InpSlopeMinATR;
   if(g_ind.adx>=InpADXTrend){
      if(g_ind.close1>g_ind.emaM&&g_ind.emaM>g_ind.emaS&&g_ind.emaF>g_ind.emaM&&g_ind.pdi>g_ind.mdi&&up)return REG_BULL;
      if(g_ind.close1<g_ind.emaM&&g_ind.emaM<g_ind.emaS&&g_ind.emaF<g_ind.emaM&&g_ind.mdi>g_ind.pdi&&dn)return REG_BEAR;
   }
   return REG_RANGE;
}
bool VolOK(){
   double ratio=g_ind.atr/g_ind.atrAvg;
   return ratio>=InpVolLowMult&&ratio<=InpVolHighMult&&g_ind.range1<=g_ind.atr*InpSpikeMult;
}
bool SpreadOK(){return g_spreadPts<=InpMaxSpreadPts&&!SpreadAbnormal();}

int ScoreTrend(int dir,string &detail){
   int s=0;detail="";double atr=g_ind.atr;
   if(dir>0){
      if(g_ind.close1>g_ind.emaM&&g_ind.emaM>g_ind.emaS&&g_ind.emaF>g_ind.emaM){s++;detail+="EMA ";}
      if((g_ind.emaF-g_ind.emaFPrev)/atr>=InpSlopeMinATR){s++;detail+="SLOPE ";}
      if(g_ind.rsi>=InpRSIBuyMin&&g_ind.rsi<=InpRSIOverbought){s++;detail+="RSI ";}
      if(g_ind.adx>=InpADXTrend&&g_ind.pdi>g_ind.mdi){s++;detail+="ADX ";}
      if(g_ind.recentLow>g_ind.priorLow&&(g_ind.close1-g_ind.emaF)<=InpMaxExtensionATR*atr){s++;detail+="STRUCT ";}
   }else{
      if(g_ind.close1<g_ind.emaM&&g_ind.emaM<g_ind.emaS&&g_ind.emaF<g_ind.emaM){s++;detail+="EMA ";}
      if((g_ind.emaFPrev-g_ind.emaF)/atr>=InpSlopeMinATR){s++;detail+="SLOPE ";}
      if(g_ind.rsi<=InpRSISellMax&&g_ind.rsi>=100.0-InpRSIOverbought){s++;detail+="RSI ";}
      if(g_ind.adx>=InpADXTrend&&g_ind.mdi>g_ind.pdi){s++;detail+="ADX ";}
      if(g_ind.recentHigh<g_ind.priorHigh&&(g_ind.emaF-g_ind.close1)<=InpMaxExtensionATR*atr){s++;detail+="STRUCT ";}
   }
   if(VolOK()){s++;detail+="VOL ";}if(SpreadOK()){s++;detail+="SPREAD ";}
   return s;
}
int ScoreRange(int dir,string &detail){
   int s=0;detail="";double atr=g_ind.atr;
   if(dir>0){
      if(g_ind.rsi<=InpRangeRSIBuy){s++;detail+="RSI ";}
      if((g_ind.emaF-g_ind.close1)>=InpRangeStretchATR*atr){s++;detail+="STRETCH ";}
      if(g_ind.close1>g_ind.open1){s++;detail+="REVERSAL ";}
   }else{
      if(g_ind.rsi>=InpRangeRSISell){s++;detail+="RSI ";}
      if((g_ind.close1-g_ind.emaF)>=InpRangeStretchATR*atr){s++;detail+="STRETCH ";}
      if(g_ind.close1<g_ind.open1){s++;detail+="REVERSAL ";}
   }
   if(g_ind.adx<InpADXRangeMax){s++;detail+="ADXLOW ";}
   if(MathAbs(g_ind.emaM-g_ind.emaMPrev)/atr<=InpFlatSlopeATR){s++;detail+="FLAT ";}
   if(VolOK()){s++;detail+="VOL ";}if(SpreadOK()){s++;detail+="SPREAD ";}
   return s;
}
void StatsInit(){ZeroMemory(g_st);}
void StatsAddBasket(double pnl,int entries,double dur){
   g_st.baskets++;g_st.totalEntries+=entries;g_st.totalDurationSec+=dur;if(entries>g_st.maxEntries)g_st.maxEntries=entries;
   if(pnl>=0){g_st.wins++;g_st.grossProfit+=pnl;if(pnl>g_st.largestWin)g_st.largestWin=pnl;g_st.consecWins++;g_st.consecLosses=0;if(g_st.consecWins>g_st.maxConsecWins)g_st.maxConsecWins=g_st.consecWins;}
   else{g_st.losses++;g_st.grossLoss+=pnl;if(pnl<g_st.largestLoss)g_st.largestLoss=pnl;g_st.consecLosses++;g_st.consecWins=0;if(g_st.consecLosses>g_st.maxConsecLosses)g_st.maxConsecLosses=g_st.consecLosses;}
}
void StatsPrint(){
   double n=(g_st.baskets>0?g_st.baskets:1);
   PrintFormat("=== XGS BASKET STATS === baskets=%d wins=%d losses=%d winrate=%.1f%%",g_st.baskets,g_st.wins,g_st.losses,100.0*g_st.wins/n);
   PrintFormat("grossProfit=%.2f grossLoss=%.2f avgWin=%.2f avgLoss=%.2f largestWin=%.2f largestLoss=%.2f",g_st.grossProfit,g_st.grossLoss,(g_st.wins>0?g_st.grossProfit/g_st.wins:0),(g_st.losses>0?g_st.grossLoss/g_st.losses:0),g_st.largestWin,g_st.largestLoss);
   PrintFormat("maxConsecWins=%d maxConsecLosses=%d avgDuration=%.0fs avgEntries=%.2f maxEntries=%d maxFloatDD=%.2f",g_st.maxConsecWins,g_st.maxConsecLosses,g_st.totalDurationSec/n,g_st.totalEntries/n,g_st.maxEntries,g_st.maxFloatDD);
}
string Snapshot(){
   double eq=AccountEquity();
   return StringFormat("spr=%.0f atr=%.3f rsi=%.1f adx=%.1f emaF=%.2f emaM=%.2f emaS=%.2f regime=%s eq=%.2f dd=%.2f%%",g_spreadPts,g_ind.atr,g_ind.rsi,g_ind.adx,g_ind.emaF,g_ind.emaM,g_ind.emaS,RegimeName(g_regime),eq,g_ddPct);
}
void CsvInit(){
   if(!InpLogCSV||g_quiet)return;
   g_csvName=StringFormat("XGS_%s_%d.csv",Symbol(),(int)InpMagic);
   int h=FileOpen(g_csvName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE){g_csvName="";return;}
   if(FileSize(h)==0)FileWrite(h,"time","symbol","event","dir","lot","price","spread","atr","rsi","adx","emaF","emaM","emaS","regime","score","basket","basketProfit","equity","ddPct");
   FileClose(h);
}
void CsvWrite(string ev,int dir,double lot,double price,int score){
   if(g_csvName=="")return;
   int h=FileOpen(g_csvName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,';');if(h==INVALID_HANDLE)return;
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),Symbol(),ev,DirText(dir),DoubleToString(lot,2),DoubleToString(price,g_digits),DoubleToString(g_spreadPts,0),DoubleToString(g_ind.atr,3),DoubleToString(g_ind.rsi,1),DoubleToString(g_ind.adx,1),DoubleToString(g_ind.emaF,2),DoubleToString(g_ind.emaM,2),DoubleToString(g_ind.emaS,2),RegimeName(g_regime),score,g_b.id,DoubleToString(g_b.profit,2),DoubleToString(AccountEquity(),2),DoubleToString(g_ddPct,2));
   FileClose(h);
}
bool IsOurOrder(){
   return OrderSymbol()==Symbol()&&(long)OrderMagicNumber()==InpMagic;
}
int CountPending(int &ticket,int &otype){
   int n=0;ticket=-1;otype=-1;
   for(int i=OrdersTotal()-1;i>=0;i--)if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)){
      if(!IsOurOrder())continue;
      int t=OrderType();
      if(t==OP_BUYSTOP||t==OP_SELLSTOP||t==OP_BUYLIMIT||t==OP_SELLLIMIT){n++;ticket=OrderTicket();otype=t;}
   }
   return n;
}
void ScanBasket(){
   int n=0,dir=0;double vol=0,pv=0,prof=0,worst=0,firstPx=0;datetime firstT=0;
   for(int i=OrdersTotal()-1;i>=0;i--)if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)){
      if(!IsOurOrder())continue;
      int t=OrderType();if(t!=OP_BUY&&t!=OP_SELL)continue;
      int d=(t==OP_BUY?1:-1);double v=OrderLots(),op=OrderOpenPrice();datetime pt=OrderOpenTime();
      dir=d;n++;vol+=v;pv+=v*op;prof+=OrderProfit()+OrderSwap()+OrderCommission();
      if(n==1)worst=op;else worst=(dir>0?MathMin(worst,op):MathMax(worst,op));
      if(firstT==0||pt<firstT){firstT=pt;firstPx=op;}
   }
   g_b.count=n;if(n==0)return;
   g_b.vol=vol;g_b.avg=pv/vol;g_b.profit=prof;g_b.dir=dir;
   if(prof>g_b.peakProfit)g_b.peakProfit=prof;if(prof<g_b.minProfit)g_b.minProfit=prof;
   if(!g_b.active){
      g_b.active=true;g_b.id=++g_basketSeq;g_b.entries=n;g_b.firstPrice=firstPx;g_b.lastPrice=worst;
      g_b.atrOpen=(g_ind.valid?g_ind.atr:0);g_b.equityOpen=AccountEquity();g_b.openTime=(firstT>0?firstT:TimeCurrent());
      g_b.peakProfit=prof;g_b.minProfit=prof;
      g_tradesToday++;g_lastEntryTime=TimeCurrent();g_lastEntryBar=g_ind.barTime;
      int k=ArraySize(g_tradeTimes);ArrayResize(g_tradeTimes,k+1);g_tradeTimes[k]=TimeCurrent();
      Log(StringFormat("BASKET #%d DETECTED dir=%s positions=%d vol=%.2f",g_b.id,DirText(dir),n,vol));
      CsvWrite("BASKET_DETECTED",dir,vol,g_b.avg,0);
   }
   g_b.entries=MathMax(g_b.entries,n);
}
void ResetBasket(){ZeroMemory(g_b);}

void FinalizeBasket(){
   double pnl=0;int deals=0;
   datetime from=g_b.openTime-1,to=TimeCurrent()+10;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)){
      if(!IsOurOrder())continue;
      if(OrderCloseTime()<from||OrderCloseTime()>to)continue;
      int t=OrderType();if(t!=OP_BUY&&t!=OP_SELL)continue;
      pnl+=OrderProfit()+OrderSwap()+OrderCommission();deals++;
   }
   if(deals==0)pnl=g_b.profit;
   double dur=(double)(TimeCurrent()-g_b.openTime);
   StatsAddBasket(pnl,g_b.entries,dur);
   if(-g_b.minProfit>g_st.maxFloatDD)g_st.maxFloatDD=-g_b.minProfit;
   if(pnl<0)g_consecLoss++;else g_consecLoss=0;
   if(InpMaxConsecLossBaskets>0&&g_consecLoss>=InpMaxConsecLossBaskets)g_consecPause=true;
   g_lastCloseTime=TimeCurrent();g_lastCloseBar=g_ind.barTime;
   string reason=(g_forceClose!=""?g_forceClose:"closed by server/external (TP/SL/stop-out)");
   g_lastTradeText=StringFormat("Basket #%d closed %.2f (%s)",g_b.id,pnl,reason);
   Log(StringFormat("BASKET #%d CLOSED pnl=%.2f entries=%d dur=%.0fs maxFloatDD=%.2f reason=%s | %s",g_b.id,pnl,g_b.entries,dur,-g_b.minProfit,reason,Snapshot()));
   CsvWrite("BASKET_CLOSED",g_b.dir,g_b.vol,g_b.avg,g_b.entries);
   g_forceClose="";ResetBasket();
}
void DeleteAllPending(string why=""){
   for(int i=OrdersTotal()-1;i>=0;i--)if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)){
      if(!IsOurOrder())continue;
      int t=OrderType();if(t!=OP_BUYSTOP&&t!=OP_SELLSTOP&&t!=OP_BUYLIMIT&&t!=OP_SELLLIMIT)continue;
      int tk=OrderTicket();
      if(!OrderDelete(tk,clrNONE))Log("PENDING delete FAILED #"+IntegerToString(tk)+" err="+IntegerToString(GetLastError()));
      else if(why!="")Log("PENDING #"+IntegerToString(tk)+" cancelled: "+why);
   }
}
void ManagePending(){
   int tk,ty;if(CountPending(tk,ty)==0)return;
   if(!OrderSelect(tk,SELECT_BY_TICKET,MODE_TRADES))return;
   double px=OrderOpenPrice();datetime exp=OrderExpiration();string why="";
   if(g_b.active)why="basket active";
   else if(exp>0&&TimeCurrent()>=exp)why="expired";
   else if(!g_ind.valid)why="indicators invalid";
   else if(!SpreadOK())why="spread too high";
   else if(ty==OP_BUYSTOP&&!(g_regime==REG_BULL||g_regime==REG_RANGE))why="regime no longer valid";
   else if(ty==OP_SELLSTOP&&!(g_regime==REG_BEAR||g_regime==REG_RANGE))why="regime no longer valid";
   else{
      double mkt=(ty==OP_BUYSTOP?g_ask:g_bid);
      if(MathAbs(px-mkt)>InpPendingMaxDistATR*g_ind.atr)why="price drifted beyond max distance";
   }
   if(why!=""){if(!OrderDelete(tk))Log("PENDING delete FAILED #"+IntegerToString(tk)+" err="+IntegerToString(GetLastError()));else Log("PENDING #"+IntegerToString(tk)+" cancelled: "+why);}
}
void ResetHalt(){g_halted=false;g_haltReason="";g_peakEq=AccountEquity();GVSet("halted",0);GVSet("peak",g_peakEq);Log("EA HALT RESET manually.");}
void DailyRollover(){
   int key=DayKey(TimeCurrent());double eq=AccountEquity();if(key==g_dayKey)return;
   g_dayKey=key;g_dayStartEq=eq;g_dailyLossHit=false;g_dailyProfitHit=false;g_consecPause=false;g_consecLoss=0;g_tradesToday=0;
   if(g_halted&&!InpManualReset){g_halted=false;g_haltReason="";g_peakEq=eq;GVSet("halted",0);}
   GVSet("dayKey",g_dayKey);GVSet("dayStartEq",g_dayStartEq);
}
void UpdateEquityCurve(double eq){
   if(!InpUseEquityCurve){g_ecPaused=false;return;}
   datetime now=TimeCurrent();if(now==g_lastEcCalc)return;g_lastEcCalc=now;
   int sz=ArraySize(g_ecBucket);if(sz<1)return;long hr=(long)(now/3600);int idx=(int)(hr%sz);if(idx<0)idx=-idx;
   if(g_ecHour[idx]!=hr){g_ecHour[idx]=hr;g_ecBucket[idx]=eq;}else if(eq>g_ecBucket[idx])g_ecBucket[idx]=eq;
   double pk=eq;for(int i=0;i<sz;i++)if(hr-g_ecHour[i]>=0&&hr-g_ecHour[i]<sz&&g_ecBucket[i]>pk)pk=g_ecBucket[i];
   g_ecPeak=pk;double dd=(pk>0?(pk-eq)/pk*100.0:0);
   if(!g_ecPaused&&dd>=InpECPausePct){g_ecPaused=true;Log(StringFormat("EQUITY CURVE PAUSE: dd %.2f%%",dd));}
   else if(g_ecPaused&&dd<=InpECResumePct)g_ecPaused=false;
}
void UpdateRisk(){
   DailyRollover();double eq=AccountEquity();
   if(eq>g_peakEq){g_peakEq=eq;GVSet("peak",g_peakEq);}
   g_ddPct=(g_peakEq>0?(g_peakEq-eq)/g_peakEq*100.0:0);
   g_dailyPct=(g_dayStartEq>0?(eq-g_dayStartEq)/g_dayStartEq*100.0:0);
   if(!g_dailyLossHit&&InpMaxDailyLossPct>0&&g_dailyPct<=-InpMaxDailyLossPct)g_dailyLossHit=true;
   if(!g_dailyProfitHit&&InpMaxDailyProfitPct>0&&g_dailyPct>=InpMaxDailyProfitPct)g_dailyProfitHit=true;
   UpdateEquityCurve(eq);
}
int CountRecentTrades(int sec){
   datetime now=TimeCurrent();int c=0;
   for(int i=ArraySize(g_tradeTimes)-1;i>=0;i--)if(now-g_tradeTimes[i]<sec)c++;
   return c;
}
void PurgeTradeTimes(){
   datetime now=TimeCurrent();int keep=0,n=ArraySize(g_tradeTimes);
   while(keep<n&&now-g_tradeTimes[keep]>=3600)keep++;
   if(keep==0)return;
   for(int i=keep;i<n;i++)g_tradeTimes[i-keep]=g_tradeTimes[i];
   ArrayResize(g_tradeTimes,n-keep);
}
bool EntriesAllowed(bool forGrid,string &why){
   why="";
   if(g_halted){why="TRADING STOPPED: halted ("+g_haltReason+") - press R";return false;}
   if(!IsTradeAllowed()||!IsExpertEnabled()){why="ENTRY REJECTED: trading not allowed";return false;}
   if(MarketInfo(Symbol(),MODE_TRADEALLOWED)==0){why="ENTRY REJECTED: symbol trading disabled";return false;}
   if(g_dailyLossHit){why="TRADING STOPPED: daily loss limit";return false;}
   if(g_dailyProfitHit){why="TRADING STOPPED: daily profit target";return false;}
   if(g_consecPause){why="TRADING STOPPED: max consecutive losing baskets";return false;}
   if(g_ecPaused){why="TRADING STOPPED: equity curve protection";return false;}
   if(InpMaxTradesPerDay>0&&g_tradesToday>=InpMaxTradesPerDay){why="TRADING STOPPED: max trades per day";return false;}
   if(g_spreadPts>InpMaxSpreadPts){why=StringFormat("ENTRY REJECTED: spread %.0f > %d",g_spreadPts,InpMaxSpreadPts);return false;}
   if(SpreadAbnormal()){why="ENTRY REJECTED: abnormal spread";return false;}
   string sw;if(!SessionOK(sw)){why="ENTRY REJECTED: "+sw;return false;}
   if(InNewsBlackout()){why="ENTRY REJECTED: news blackout";return false;}
   datetime now=TimeCurrent();
   if(InpMinSecBetweenTrades>0&&g_lastEntryTime>0&&now-g_lastEntryTime<InpMinSecBetweenTrades){why="ENTRY REJECTED: min seconds between trades";return false;}
   if(InpMinBarsBetweenEntries>0&&g_lastEntryBar>0&&g_ind.barTime>0){
      int bars=iBarShift(NULL,0,g_lastEntryBar,false);if(bars>=0&&bars<InpMinBarsBetweenEntries){why="ENTRY REJECTED: min bars between entries";return false;}
   }
   if(InpMaxTradesPerMinute>0&&CountRecentTrades(60)>=InpMaxTradesPerMinute){why="ENTRY REJECTED: max trades per minute";return false;}
   if(InpMaxTradesPerHour>0&&CountRecentTrades(3600)>=InpMaxTradesPerHour){why="ENTRY REJECTED: max trades per hour";return false;}
   if(!forGrid){
      if(g_lastCloseTime>0&&now-g_lastCloseTime<InpCooldownAfterCloseSec){why="ENTRY REJECTED: cooldown after basket close";return false;}
      if(InpNewBarAfterClose&&g_lastCloseBar>0&&g_ind.barTime<=g_lastCloseBar){why="ENTRY REJECTED: waiting for new bar";return false;}
   }
   return true;
}
double ComputeLot(){
   double lot=InpFixedLot;
   if(InpLotMode==LOT_RISK&&g_ind.valid){
      double dist=g_ind.atr*(InpSL_ATR>0?InpSL_ATR:InpEmergencySL_ATR);
      double lossPerLot=dist*MoneyPerPriceUnitPerLot();
      if(lossPerLot>0)lot=(AccountEquity()*InpRiskPercent/100.0/lossPerLot)/MathMax(1,InpMaxPositions);
   }
   lot=MathMin(lot,InpMaxLot);double v=NormVol(lot);if(v<=0)v=g_volMin;return v;
}
bool ExposureOK(int dir,double lot,double price,string &why){
   if(lot>InpMaxLot+1e-9){why="REJECTED: lot above MaxLot";return false;}
   double cur=(g_b.active?g_b.vol:0);if(cur+lot>InpMaxBasketLots+1e-9){why="GRID REJECTED: max basket lots reached";return false;}
   ResetLastError();
   double fm=AccountFreeMarginCheck(Symbol(),dir>0?OP_BUY:OP_SELL,lot);
   if(fm<=0||GetLastError()==134){why="ENTRY REJECTED: insufficient free margin";return false;}
   double eq=AccountEquity(),used=AccountMargin();
   if(eq>0&&(used+(eq-fm))/eq*100.0>InpMaxMarginUsage){why=StringFormat("ENTRY REJECTED: margin usage > %.0f%%",InpMaxMarginUsage);return false;}
   return true;
}
void ApplyEmergencySL(){
   if(!InpUseEmergencySL||!g_b.active||g_b.atrOpen<=0)return;
   double dist=g_b.atrOpen*InpEmergencySL_ATR;
   double sl=NormPrice(g_b.dir>0?g_b.firstPrice-dist:g_b.firstPrice+dist);
   double minDist=(g_stopsLevel+2)*g_point;
   if(g_b.dir>0&&sl>g_bid-minDist)return;
   if(g_b.dir<0&&sl<g_ask+minDist)return;
   for(int i=OrdersTotal()-1;i>=0;i--)if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)){
      if(!IsOurOrder())continue;int t=OrderType();if(t!=OP_BUY&&t!=OP_SELL)continue;
      double cur=OrderStopLoss();if(MathAbs(cur-sl)<g_point*0.5)continue;
      ResetLastError();
      if(!OrderModify(OrderTicket(),OrderOpenPrice(),sl,OrderTakeProfit(),0,clrNONE))
         Log("EMERGENCY SL modify failed #"+IntegerToString(OrderTicket())+" err="+IntegerToString(GetLastError()));
   }
}
bool OpenMarket(int dir,double lot,int score,string note){
   int type=(dir>0?OP_BUY:OP_SELL);string cmt=InpComment+"#"+IntegerToString(g_b.active?g_b.id:g_basketSeq+1);
   bool ok=false;int tk=-1;double price=0;
   for(int a=0;a<MathMax(1,InpMaxRetries);a++){
      RefreshRates();price=(dir>0?Ask:Bid);ResetLastError();
      tk=OrderSend(Symbol(),type,lot,price,InpSlippage,0,0,cmt,(int)InpMagic,0,clrNONE);
      if(tk>0){ok=true;break;}
      int e=GetLastError();Log(StringFormat("ORDER FAILED attempt %d %s lot=%.2f err=%d",a+1,DirText(dir),lot,e));
      if(!(e==4||e==6||e==128||e==129||e==135||e==136||e==137||e==138||e==146))break;
      Sleep(150);
   }
   if(!ok)return false;
   if(!g_b.active){
      ResetBasket();g_b.active=true;g_b.id=++g_basketSeq;g_b.dir=dir;g_b.entries=0;
      g_b.firstPrice=price;g_b.atrOpen=g_ind.atr;g_b.openTime=TimeCurrent();g_b.equityOpen=AccountEquity();
   }
   g_b.entries++;g_b.lastPrice=price;g_tradesToday++;g_lastEntryTime=TimeCurrent();g_lastEntryBar=g_ind.barTime;
   int k=ArraySize(g_tradeTimes);ArrayResize(g_tradeTimes,k+1);g_tradeTimes[k]=TimeCurrent();
   g_lastTradeText=StringFormat("%s %.2f @ %s (#%d lvl %d)",DirText(dir),lot,DoubleToString(price,g_digits),g_b.id,g_b.entries);
   ScanBasket();Log(StringFormat("TRADE %s %s lot=%.2f price=%s score=%d basket=#%d level=%d basketProfit=%.2f | %s | %s",DirText(dir),Symbol(),lot,DoubleToString(price,g_digits),score,g_b.id,g_b.entries,g_b.profit,note,Snapshot()));
   CsvWrite("ENTRY",dir,lot,price,score);ApplyEmergencySL();return true;
}
void CloseBasket(string reason){
   if(g_forceClose=="")g_forceClose=reason;
   Log(StringFormat("CLOSING BASKET #%d: %s | profit=%.2f vol=%.2f",g_b.id,reason,g_b.profit,g_b.vol));
   for(int i=OrdersTotal()-1;i>=0;i--)if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)){
      if(!IsOurOrder())continue;int t=OrderType();if(t!=OP_BUY&&t!=OP_SELL)continue;
      bool done=false;
      for(int a=0;a<MathMax(1,InpMaxRetries)&&!done;a++){
         RefreshRates();double cp=(t==OP_BUY?Bid:Ask);ResetLastError();
         if(OrderClose(OrderTicket(),OrderLots(),cp,InpSlippage,clrNONE)){done=true;break;}
         int e=GetLastError();Log(StringFormat("CLOSE FAILED ticket=%d attempt=%d err=%d",OrderTicket(),a+1,e));
         if(!(e==4||e==6||e==128||e==129||e==135||e==136||e==137||e==138||e==146))break;
         Sleep(150);
      }
   }
   DeleteAllPending();ScanBasket();
}
void ManageBasket(){
   if(!g_b.active||g_b.count==0)return;
   if(g_forceClose!=""){CloseBasket(g_forceClose);return;}
   double eq=AccountEquity(),vpu=MoneyPerPriceUnitPerLot(),spreadPx=g_ask-g_bid,atr0=(g_b.atrOpen>0?g_b.atrOpen:g_ind.atr);
   if(InpMaxEquityDDPct>0&&g_ddPct>=InpMaxEquityDDPct){
      g_halted=true;g_haltReason=StringFormat("equity DD %.2f%%",g_ddPct);GVSet("halted",1);CloseBasket("MAX EQUITY DRAWDOWN");return;
   }
   if(InpCloseBasketOnDailyLoss&&g_dailyLossHit){CloseBasket("DAILY LOSS LIMIT");return;}
   MqlDateTime d;TimeToStruct(TimeCurrent(),d);
   if(d.day_of_week==5&&InpFridayCloseHour>0&&d.hour>=InpFridayCloseHour){CloseBasket("FRIDAY CLOSE");return;}
   if(InpCloseBasketInNews&&InNewsBlackout()){CloseBasket("NEWS BLACKOUT");return;}
   if(InpCloseOnExtremeVol&&g_ind.valid&&g_ind.atr/g_ind.atrAvg>InpVolExtremeMult){CloseBasket("EXTREME VOLATILITY");return;}
   double tpMoney=0;
   if(InpTPMode==TP_ATR){double dist=MathMax(atr0*InpTP_ATR,spreadPx*InpMinTPSpreadMult);tpMoney=dist*g_b.vol*vpu;}
   else if(InpTPMode==TP_MONEY)tpMoney=InpTP_Money;
   else if(InpTPMode==TP_EQUITY_PCT)tpMoney=eq*InpTP_EquityPct/100.0;
   double slMoney=1.0e100;string slWhy="";
   if(InpSL_Money>0){slMoney=InpSL_Money;slWhy="MONEY";}
   if(InpSL_EquityPct>0){double v=g_b.equityOpen*InpSL_EquityPct/100.0;if(v<slMoney){slMoney=v;slWhy="EQUITY%";}}
   if(InpSL_ATR>0){double v=atr0*InpSL_ATR*g_b.vol*vpu;if(v<slMoney){slMoney=v;slWhy="ATR";}}
   g_tpMoneyCache=tpMoney;g_slMoneyCache=(slMoney>=1.0e99?0:slMoney);
   if(tpMoney>0&&g_b.profit>=tpMoney){CloseBasket(StringFormat("BASKET TP %.2f >= %.2f",g_b.profit,tpMoney));return;}
   if(slMoney<1.0e99&&g_b.profit<=-slMoney){CloseBasket(StringFormat("BASKET SL (%s) %.2f <= -%.2f",slWhy,g_b.profit,slMoney));return;}
   if(g_b.entries>=InpMaxPositions&&InpFinalLevelATR>0){
      double adverse=(g_b.dir>0?g_b.lastPrice-g_bid:g_ask-g_b.lastPrice);
      if(adverse>=InpFinalLevelATR*atr0){CloseBasket("MAX GRID LEVELS STOP");return;}
   }
   if(InpUseTrail&&tpMoney>0){
      double arm=tpMoney*InpTrailStartPctTP/100.0;
      if(g_b.peakProfit>=arm){
         double floorV=MathMax(g_b.peakProfit*(1.0-InpTrailGiveBackPct/100.0),InpMinLockMoney);
         if(g_b.profit<=floorV){CloseBasket(StringFormat("BASKET TRAIL peak=%.2f now=%.2f",g_b.peakProfit,g_b.profit));return;}
      }
   }
}
void TryGridAdd(){
   if(!g_b.active||g_b.count==0||g_forceClose!=""||!g_ind.valid)return;
   if(g_b.entries>=InpMaxPositions){Reject("GRID REJECTED: max positions reached");return;}
   double mult=0;
   if(g_regime==REG_RANGE)mult=InpGridATR_Range;
   else if(g_regime==REG_BULL&&g_b.dir>0)mult=InpGridATR_Trend;
   else if(g_regime==REG_BEAR&&g_b.dir<0)mult=InpGridATR_Trend;
   else if(g_regime==REG_HIGHVOL&&InpGridInHighVol)mult=InpGridATR_HighVol;
   if(mult<=0){Reject("GRID REJECTED: regime "+RegimeName(g_regime));return;}
   double dist=MathMax(g_ind.atr*mult,(g_ask-g_bid)*InpMinGridSpreadMult);
   bool trigger=(g_b.dir>0?(g_ask<=g_b.lastPrice-dist):(g_bid>=g_b.lastPrice+dist));if(!trigger)return;
   string why;if(!EntriesAllowed(true,why)){Reject("GRID REJECTED: "+why);return;}
   double lot=ComputeLot(),px=(g_b.dir>0?g_ask:g_bid);if(!ExposureOK(g_b.dir,lot,px,why)){Reject(why);return;}
   OpenMarket(g_b.dir,lot,0,StringFormat("GRID level %d dist=%.2f mult=%.2f",g_b.entries+1,dist,mult));
}
bool PlacePending(int dir,double lot,int score,string note){
   int type=(dir>0?OP_BUYSTOP:OP_SELLSTOP);double offset=MathMax(g_ind.atr*InpPendingOffsetATR,(MathMax(g_stopsLevel,g_freezeLevel)+3)*g_point);
   RefreshRates();double price=NormPrice(dir>0?Ask+offset:Bid-offset);datetime exp=TimeCurrent()+InpPendingExpirySec;
   for(int a=0;a<MathMax(1,InpMaxRetries);a++){
      ResetLastError();int tk=OrderSend(Symbol(),type,lot,price,InpSlippage,0,0,InpComment+"#P",(int)InpMagic,exp,clrNONE);
      if(tk>0){Log(StringFormat("PENDING %s placed lot=%.2f price=%s expiry=%s score=%d | %s",PendingDirText(dir),lot,DoubleToString(price,g_digits),TimeToString(exp,TIME_SECONDS),score,note));g_lastTradeText=StringFormat("Pending %s @ %s",PendingShortText(dir),DoubleToString(price,g_digits));g_lastEntryTime=TimeCurrent();return true;}
      int e=GetLastError();Log(StringFormat("PENDING FAILED attempt %d err=%d",a+1,e));
      if(!(e==4||e==6||e==128||e==129||e==135||e==136||e==137||e==138||e==146))break;Sleep(150);
   }
   return false;
}
void EvaluateEntry(){
   if(g_b.active||!g_ind.valid)return;
   int pt,pty;if(CountPending(pt,pty)>0)return;
   if(g_regime==REG_UNSAFE||g_regime==REG_HIGHVOL||g_regime==REG_LOWVOL){Reject("ENTRY REJECTED: regime "+RegimeName(g_regime));return;}
   string why;if(!EntriesAllowed(false,why)){Reject(why);return;}
   int dir=0,score=0;string det="";
   if(g_regime==REG_BULL){dir=1;score=ScoreTrend(1,det);}
   else if(g_regime==REG_BEAR){dir=-1;score=ScoreTrend(-1,det);}
   else{string d1,d2;int sb=ScoreRange(1,d1),ss=ScoreRange(-1,d2);if(sb>=ss){dir=1;score=sb;det=d1;}else{dir=-1;score=ss;det=d2;}}
   if(score<InpMinScore){Reject(StringFormat("ENTRY REJECTED: score %d/7 < %d [%s]",score,InpMinScore,det));return;}
   double lot=ComputeLot(),px=(dir>0?g_ask:g_bid);if(!ExposureOK(dir,lot,px,why)){Reject(why);return;}
   string note=StringFormat("%s score=%d/7 [%s]",RegimeName(g_regime),score,det);
   if(InpUsePending)PlacePending(dir,lot,score,note);else OpenMarket(dir,lot,score,note);
}

void DashRow(int row,string txt,color clr){
   string nm=PFX+"R"+IntegerToString(row);
   if(ObjectFind(0,nm)<0){
      ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,14);ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,24+row*15);
      ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,9);ObjectSetString(0,nm,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
   }
   ObjectSetString(0,nm,OBJPROP_TEXT,txt);ObjectSetInteger(0,nm,OBJPROP_COLOR,clr);
}
string EmaTrendText(){
   if(!g_ind.valid)return "n/a";
   if(g_ind.emaF>g_ind.emaM&&g_ind.emaM>g_ind.emaS)return "UP (20>50>200)";
   if(g_ind.emaF<g_ind.emaM&&g_ind.emaM<g_ind.emaS)return "DOWN (20<50<200)";
   return "MIXED";
}
void UpdateDashboard(){
   if(!InpDashboard||(g_tester&&!g_visual))return;
   string bg=PFX+"BG";
   if(ObjectFind(0,bg)<0){
      ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,6);ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,16);
      ObjectSetInteger(0,bg,OBJPROP_XSIZE,350);ObjectSetInteger(0,bg,OBJPROP_YSIZE,24*15+24);
      ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,clrBlack);ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);ObjectSetInteger(0,bg,OBJPROP_COLOR,clrDimGray);
      ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
   }
   color W=clrWhite,G=clrLimeGreen,R=clrTomato,Y=clrGold,C=clrDeepSkyBlue;
   string sw;
   bool sess=SessionOK(sw);
   string riskTxt="OK";
   color riskClr=G;
   if(g_halted){riskTxt="HALTED: "+g_haltReason;riskClr=R;}else if(g_dailyLossHit){riskTxt="DAILY LOSS LIMIT";riskClr=R;}else if(g_dailyProfitHit){riskTxt="DAILY TARGET";riskClr=Y;}else if(g_consecPause){riskTxt="CONSEC LOSS PAUSE";riskClr=R;}else if(g_ecPaused){riskTxt="EQUITY CURVE PAUSE";riskClr=Y;}
   bool on=!(g_halted||g_dailyLossHit||g_dailyProfitHit||g_consecPause||g_ecPaused);int r=0;
   DashRow(r++,"XAU GRID SCALPER | "+Symbol()+" "+IntegerToString(Period()),C);
   DashRow(r++,"Server time : "+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),W);
   DashRow(r++,"Account     : MT4 HEDGING",W);
   DashRow(r++,"Trading     : "+TradingStatusText(on,sess,sw),(on&&sess)?G:Y);
   DashRow(r++,"Regime      : "+RegimeName(g_regime),(g_regime==REG_BULL?G:(g_regime==REG_BEAR?R:(g_regime==REG_RANGE?C:Y))));
   DashRow(r++,StringFormat("Spread      : %.0f pts (avg %.1f, max %d)",g_spreadPts,g_spreadAvg,InpMaxSpreadPts),SpreadOK()?W:R);
   DashRow(r++,StringFormat("ATR         : %.3f (avg %.3f, x%.2f)",g_ind.atr,g_ind.atrAvg,g_ind.atrAvg>0?g_ind.atr/g_ind.atrAvg:0),W);
   DashRow(r++,StringFormat("RSI / ADX   : %.1f / %.1f (+DI %.1f -DI %.1f)",g_ind.rsi,g_ind.adx,g_ind.pdi,g_ind.mdi),W);
   DashRow(r++,"EMA trend   : "+EmaTrendText(),W);
   DashRow(r++,"Basket dir  : "+BasketDirText(),g_b.active?C:W);
   DashRow(r++,StringFormat("Positions   : %d (entries %d / %d)",g_b.count,g_b.entries,InpMaxPositions),W);
   DashRow(r++,StringFormat("Total lots  : %.2f / %.2f",g_b.vol,InpMaxBasketLots),W);
   DashRow(r++,StringFormat("Basket P/L  : %.2f (peak %.2f)",g_b.profit,g_b.peakProfit),g_b.profit>=0?G:R);
   DashRow(r++,StringFormat("Basket TP/SL: +%.2f / -%.2f",g_tpMoneyCache,g_slMoneyCache),W);
   DashRow(r++,StringFormat("Daily P/L   : %.2f%% (%.2f)",g_dailyPct,AccountEquity()-g_dayStartEq),g_dailyPct>=0?G:R);
   DashRow(r++,StringFormat("Equity      : %.2f peak %.2f",AccountEquity(),g_peakEq),W);
   DashRow(r++,StringFormat("Drawdown    : %.2f%% (hard %.1f%%)",g_ddPct,InpMaxEquityDDPct),g_ddPct<InpMaxEquityDDPct*0.6?G:R);
   DashRow(r++,StringFormat("Trades today: %d / %d",g_tradesToday,InpMaxTradesPerDay),W);
   DashRow(r++,StringFormat("Baskets     : %d W%d L%d consecL %d",g_st.baskets,g_st.wins,g_st.losses,g_consecLoss),W);
   DashRow(r++,"Last trade  : "+g_lastTradeText,W);
   DashRow(r++,"Risk status : "+riskTxt,riskClr);
   DashRow(r++,"Press 'R' on chart to reset a halt",clrSilver);
   ChartRedraw();
}
void DashboardDelete(){
   for(int i=ObjectsTotal()-1;i>=0;i--){string n=ObjectName(i);if(StringFind(n,PFX)==0)ObjectDelete(n);}
}

int OnInit(){
   g_tester=IsTesting();g_visual=IsVisualMode();g_quiet=(IsOptimization()||!InpVerbose)&&!g_visual;
   if(InpMaxPositions<1||InpFixedLot<=0||InpMaxLot<=0||InpMaxBasketLots<=0||InpEmaFast>=InpEmaMid||InpEmaMid>=InpEmaSlow||InpATRAvgBars<10||InpMinScore<1||InpMinScore>7){Print("INIT FAILED: invalid inputs.");return INIT_PARAMETERS_INCORRECT;}
   if(InpMaxSpreadPts<=0||InpSlopeBars<1||InpStructBars<3||InpECLookbackHours<2){Print("INIT FAILED: invalid inputs.");return INIT_PARAMETERS_INCORRECT;}
   g_point=MarketInfo(Symbol(),MODE_POINT);g_tickSize=MarketInfo(Symbol(),MODE_TICKSIZE);g_tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
   g_volMin=MarketInfo(Symbol(),MODE_MINLOT);g_volMax=MarketInfo(Symbol(),MODE_MAXLOT);g_volStep=MarketInfo(Symbol(),MODE_LOTSTEP);g_digits=(int)MarketInfo(Symbol(),MODE_DIGITS);
   g_stopsLevel=(int)MarketInfo(Symbol(),MODE_STOPLEVEL);g_freezeLevel=(int)MarketInfo(Symbol(),MODE_FREEZELEVEL);
   if(g_point<=0||g_tickSize<=0||g_tickValue<=0||g_volMin<=0){Print("INIT FAILED: incomplete symbol specification");return INIT_FAILED;}
   if(StringFind(Symbol(),"XAU")<0&&StringFind(Symbol(),"GOLD")<0)Print("WARNING: symbol does not look like gold; defaults are tuned for XAUUSD.");
   if(InpFixedLot<g_volMin)Print("WARNING: FixedLot below broker minimum; minimum will be used.");
   if(g_volMin>InpMaxLot+1e-9)Print("WARNING: broker minimum lot exceeds MaxLot.");
   ZeroMemory(g_ind);ResetBasket();StatsInit();ArrayResize(g_tradeTimes,0);
   ArrayResize(g_ecBucket,InpECLookbackHours);ArrayResize(g_ecHour,InpECLookbackHours);ArrayInitialize(g_ecBucket,0);ArrayInitialize(g_ecHour,-1000000);
   double eq=AccountEquity();g_dayKey=(int)GVGet("dayKey",0);g_dayStartEq=GVGet("dayStartEq",eq);g_peakEq=MathMax(GVGet("peak",eq),eq);g_halted=GVGet("halted",0)>0.5;
   if(g_halted)g_haltReason="restored from previous session (hard drawdown)";
   if(g_dayKey!=DayKey(TimeCurrent())){g_dayKey=0;DailyRollover();}
   ParseNews();CsvInit();EventSetTimer(1);g_ready=true;
   PrintFormat("XGS MT4 init OK | %s | server %s | point=%.5f tick=%.5f tickValue=%.4f vol[min=%.2f max=%.2f step=%.2f] digits=%d stops=%d freeze=%d",Symbol(),TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),g_point,g_tickSize,g_tickValue,g_volMin,g_volMax,g_volStep,g_digits,g_stopsLevel,g_freezeLevel);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){EventKillTimer();if(!g_quiet||g_tester)StatsPrint();DashboardDelete();}
void OnTick(){
   if(!g_ready)return;
   if(!RefreshMarket())return;
   datetime bt=iTime(NULL,0,0);g_newBar=(bt!=g_lastBarTime&&bt>0);
   if(g_newBar){
      if(RefreshIndicators()){g_lastBarTime=bt;g_tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);PurgeTradeTimes();}
      else{g_newBar=false;if(!g_ind.valid)Reject("INDICATORS NOT READY");}
   }
   if(!g_ind.valid)return;
   UpdateRisk();g_regime=ClassifyRegime();
   ScanBasket();
   if(g_b.active&&g_b.count==0)FinalizeBasket();
   ManagePending();ManageBasket();
   if(g_b.active&&g_b.count>0)TryGridAdd();else if(g_newBar&&!g_b.active)EvaluateEntry();
}
void OnTimer(){if(!g_ready)return;UpdateDashboard();}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam){if(id==CHARTEVENT_KEYDOWN&&lparam==82&&g_halted)ResetHalt();}
double OnTester(){
   double np=TesterStatistics(STAT_PROFIT),ddMoney=TesterStatistics(STAT_EQUITY_DD),pf=TesterStatistics(STAT_PROFIT_FACTOR),trades=TesterStatistics(STAT_TRADES);
   if(ddMoney<=0)ddMoney=1;if(trades<InpMinTradesOpt)return -1;
   double rf=np/ddMoney,sample=MathMin(1.0,trades/300.0),pfPen=(pf<1.1?0.5:1.0);return rf*sample*pfPen;
}
//+------------------------------------------------------------------+
