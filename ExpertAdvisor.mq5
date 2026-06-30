//+------------------------------------------------------------------+
//|                                                DynamicEMA_EA.mq5 |
//|                                  Copyright 2023, Algorithmic Dev |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Algorithmic Dev"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Include standard library trade class
#include <Trade\Trade.mqh>

//--- Input Group: Risk and Money Management
input group "--- Risk & Money Management ---"
input double             InpRiskPercent       = 1.0;       // Risk Percent per Trade
input double             InpDefaultLotSize    = 0.01;      // Default/Minimum Lot Size
input double             InpATRMultiplier     = 1.5;       // ATR Multiplier for Stop Loss
input double             InpRRRatio           = 1.5;       // Risk-to-Reward Ratio (TP = SL * RR)

//--- Input Group: Strategy Parameters
input group "--- Strategy Parameters ---"
input int                InpFastMAPeriod      = 9;         // Fast EMA Period
input int                InpSlowMAPeriod      = 21;        // Slow EMA Period
input ENUM_MA_METHOD     InpMAMethod          = MODE_EMA;  // Moving Average Method
input int                InpATRPeriod         = 14;        // ATR Period

//--- Input Group: Execution Settings
input group "--- Execution Settings ---"
input ulong              InpMagicNumber       = 102938;    // Expert Magic Number
input ulong              InpSlippage          = 30;        // Slippage in Points

//--- Global Variables
CTrade      trade;
int         h_fast_ma;
int         h_slow_ma;
int         h_atr;
datetime    last_bar_time;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Reset the bar tracker to ensure signal evaluation starts fresh
   last_bar_time = 0;

   // Set up trading configuration
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   
   // Handle execution filling mode automatically
   trade.SetTypeFillingBySymbol(_Symbol);

   // Initialize indicator handles
   h_fast_ma = iMA(_Symbol, _Period, InpFastMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   h_slow_ma = iMA(_Symbol, _Period, InpSlowMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   h_atr     = iATR(_Symbol, _Period, InpATRPeriod);

   // Validate handles
   if(h_fast_ma == INVALID_HANDLE || h_slow_ma == INVALID_HANDLE || h_atr == INVALID_HANDLE)
   {
      Print("Error: Failed to initialize indicator handles.");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles to free up system memory
   IndicatorRelease(h_fast_ma);
   IndicatorRelease(h_slow_ma);
   IndicatorRelease(h_atr);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Strictly check signals and execute transactions on bar completion
   if(!IsNewBar()) return;

   // Check if data is synchronized and calculated properly
   if(BarsCalculated(h_fast_ma) < 5 || BarsCalculated(h_slow_ma) < 5 || BarsCalculated(h_atr) < 5) return;

   // Declare buffers to read historical data (Index 1 is the most recently completed bar)
   double fast_ma[3], slow_ma[3], atr[2];
   
   if(CopyBuffer(h_fast_ma, 0, 0, 3, fast_ma) < 3) return;
   if(CopyBuffer(h_slow_ma, 0, 0, 3, slow_ma) < 3) return;
   if(CopyBuffer(h_atr, 0, 0, 2, atr) < 2) return;

   // Do not open parallel trades if a trade managed by this EA is active
   if(HasOpenPositions()) return;

   // Evaluate EMA Cross over completed bars
   bool bull_cross = (fast_ma[1] > slow_ma[1]) && (fast_ma[2] <= slow_ma[2]);
   bool bear_cross = (fast_ma[1] < slow_ma[1]) && (fast_ma[2] >= slow_ma[2]);

   if(!bull_cross && !bear_cross) return;

   // Gather market environment parameters
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Base Stop Loss calculation on the ATR of the completed bar
   double atr_val = atr[1];
   double sl_distance = atr_val * InpATRMultiplier;
   
   // Check against the broker's minimum STOP LEVEL limitation
   double stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(stops_level == 0) stops_level = 10 * _Point; // Default safety cushion of 10 points
   
   if(sl_distance < stops_level)
   {
      sl_distance = stops_level + (5 * _Point);
   }

   // Dynamically calculate trade allocation
   double lot_size = CalculateLotSize(sl_distance);

   // Execute trades
   if(bull_cross)
   {
      double sl = ask - sl_distance;
      double tp = ask + (sl_distance * InpRRRatio);
      
      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);
      
      trade.Buy(lot_size, _Symbol, ask, sl, tp, "EMA Cross Buy");
   }
   else if(bear_cross)
   {
      double sl = bid + sl_distance;
      double tp = bid - (sl_distance * InpRRRatio);
      
      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);
      
      trade.Sell(lot_size, _Symbol, bid, sl, tp, "EMA Cross Sell");
   }
}

//+------------------------------------------------------------------+
//| Tracks transition to a new bar                                   |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime current_bar_time = iTime(_Symbol, _Period, 0);
   if(current_bar_time == 0) return false;
   if(current_bar_time != last_bar_time)
   {
      last_bar_time = current_bar_time;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculates trade size based on risk parameters                    |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_distance_price)
{
   if(sl_distance_price <= 0) return InpDefaultLotSize;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * (InpRiskPercent / 100.0);
   
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   if(tick_size == 0 || tick_value == 0) return InpDefaultLotSize;
   
   double sl_points = sl_distance_price / _Point;
   double point_value = (tick_value / tick_size) * _Point;
   double calculated_lot = risk_amount / (sl_points * point_value);
   
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Handle dynamic minimum constraints. Force strictly to 0.01 (or minimum step)
   if(calculated_lot < min_lot)
   {
      calculated_lot = min_lot;
   }
   else
   {
      calculated_lot = MathRound(calculated_lot / lot_step) * lot_step;
      if(calculated_lot > max_lot) calculated_lot = max_lot;
   }
   
   return NormalizeDouble(calculated_lot, 2);
}

//+------------------------------------------------------------------+
//| Checks if the EA currently manages any open position             |
//+------------------------------------------------------------------+
bool HasOpenPositions()
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            return true;
         }
      }
   }
   return false;
}