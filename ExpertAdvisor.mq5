//+------------------------------------------------------------------+
//|                                                 EMA_Crossover.mq5|
//|                                  Copyright 2023, Algorithmic Trader|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Include Trade library
#include <Trade\Trade.mqh>

//--- Input Parameters
input group "--- Risk & Money Management ---"
input double   InpRiskPercent       = 1.0;       // Risk Percent per Trade
input int      InpStopLossPoints    = 300;       // Stop Loss in Points (e.g., 30 pips)
input int      InpTakeProfitPoints   = 450;       // Take Profit in Points (1:1.5 Risk-to-Reward)
input ulong    InpMagicNumber       = 123456;    // Magic Number

input group "--- Indicator Settings ---"
input int      InpFastMAPeriod      = 12;        // Fast EMA Period
input int      InpSlowMAPeriod      = 26;        // Slow EMA Period
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE; // Applied Price

//--- Global Variables
CTrade      trade;
int         fastMAHandle;
int         slowMAHandle;
datetime    lastBarTime;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set magic number for the trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   
   // Initialize indicators
   fastMAHandle = iMA(_Symbol, _Period, InpFastMAPeriod, 0, MODE_EMA, InpAppliedPrice);
   slowMAHandle = iMA(_Symbol, _Period, InpSlowMAPeriod, 0, MODE_EMA, InpAppliedPrice);
   
   if(fastMAHandle == INVALID_HANDLE || slowMAHandle == INVALID_HANDLE)
   {
      Print("Failed to initialize indicators. EA stopped.");
      return(INIT_FAILED);
   }
   
   lastBarTime = 0;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   IndicatorRelease(fastMAHandle);
   IndicatorRelease(slowMAHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for bar close (execute entry logic only when a new bar starts)
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == lastBarTime)
   {
      return; 
   }
   
   // Check if we already have an open position with this magic number on this symbol
   if(HasOpenPosition())
   {
      return;
   }

   // Retrieve indicator values
   double fastValues[3];
   double slowValues[3];
   
   if(CopyBuffer(fastMAHandle, 0, 1, 2, fastValues) < 2 ||
      CopyBuffer(slowMAHandle, 0, 1, 2, slowValues) < 2)
   {
      Print("Failed to copy indicator buffer data.");
      return;
   }
   
   // fastValues[0] is Bar 2, fastValues[1] is Bar 1 (most recently completed bar)
   double fastPrev = fastValues[0];
   double fastCurr = fastValues[1];
   double slowPrev = slowValues[0];
   double slowCurr = slowValues[1];
   
   // Check Crossover signals
   bool buySignal  = (fastPrev <= slowPrev && fastCurr > slowCurr);
   bool sellSignal = (fastPrev >= slowPrev && fastCurr < slowCurr);
   
   if(buySignal)
   {
      ExecuteBuy();
      lastBarTime = currentBarTime; // Lock to prevent multi-executions on the same bar
   }
   else if(sellSignal)
   {
      ExecuteSell();
      lastBarTime = currentBarTime; // Lock to prevent multi-executions on the same bar
   }
}

//+------------------------------------------------------------------+
//| Execute a Buy order with dynamic lot size                        |
//+------------------------------------------------------------------+
void ExecuteBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slPrice = NormalizeDouble(ask - (InpStopLossPoints * _Point), _Digits);
   double tpPrice = NormalizeDouble(ask + (InpTakeProfitPoints * _Point), _Digits);
   
   double lotSize = CalculateLotSize(InpStopLossPoints);
   
   if(!trade.Buy(lotSize, _Symbol, ask, slPrice, tpPrice, "EMA Crossover Buy"))
   {
      Print("Error opening BUY position: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Execute a Sell order with dynamic lot size                       |
//+------------------------------------------------------------------+
void ExecuteSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPrice = NormalizeDouble(bid + (InpStopLossPoints * _Point), _Digits);
   double tpPrice = NormalizeDouble(bid - (InpTakeProfitPoints * _Point), _Digits);
   
   double lotSize = CalculateLotSize(InpStopLossPoints);
   
   if(!trade.Sell(lotSize, _Symbol, bid, slPrice, tpPrice, "EMA Crossover Sell"))
   {
      Print("Error opening SELL position: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calculate Trade Lot Size based on strictly enforced constraints  |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPercent / 100.0);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue <= 0 || tickSize <= 0 || slPoints <= 0)
   {
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   }
   
   // Convert points to ticks
   double pointsToTicks = slPoints * (_Point / tickSize);
   double riskPerLot = pointsToTicks * tickValue;
   
   double calculatedLot = riskAmount / riskPerLot;
   
   // Adjust lot size to broker specifications
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   calculatedLot = MathFloor(calculatedLot / lotStep) * lotStep;
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   // Clamp trade sizes
   if(calculatedLot < minLot)
   {
      calculatedLot = minLot; // Dynamic override to 0.01 lot minimum
   }
   if(calculatedLot > maxLot)
   {
      calculatedLot = maxLot;
   }
   
   return NormalizeDouble(calculatedLot, 2);
}

//+------------------------------------------------------------------+
//| Check if Expert Advisor already has active positions            |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong positionTicket = PositionGetTicket(i);
      if(positionTicket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            return true;
         }
      }
   }
   return false;
}