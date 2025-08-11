//+------------------------------------------------------------------+
//|                                   OscillatorEA_Refactored.mq5 |
//|                                  Copyright 2024, YOUR NAME HERE |
//|                                             https://example.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Refactored by Jules"
#property link      "https://www.mql5.com"
#property version   "2.00" // Refactored Version
#property strict
#property description "A professionally refactored Expert Advisor based on RSI, Stochastic, and MACD indicators."
#property description "This EA opens one trade at a time when all indicators align for a buy or sell signal."
#property description "Includes dynamic Take Profit, Stop Loss, and a Trailing Stop."

#include <Trade/Trade.mqh>

//--- ENUMERATIONS
enum ENUM_MACD_FILTER_MODE
{
    FILTER_DISABLED,       // MACD filter is not used
    FILTER_TREND,          // Trade only in the direction of the MACD trend
};

//--- INPUTS
input group "--- Magic Number & Comment ---"
input ulong  InpMagicNumber = 12345;      // EA Magic Number
input string InpEaComment   = "OscillatorEA"; // Comment for trades

input group "--- Lot Sizing ---"
input double InpLots = 0.01;              // Fixed lot size

input group "--- Position Management ---"
input double InpTpPercent        = 1.0;  // Take Profit as a percentage of the entry price
input double InpSlPercent        = 0.5;  // Stop Loss as a percentage of the entry price
input double InpTslPercent       = 0.5;  // Trailing Stop Loss as a percentage of the price move
input double InpTslTriggerPercent = 0.2; // Price move percentage to trigger the trailing stop

input group "--- Indicator Timeframes ---"
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_H1;  // Timeframe for RSI and Stochastic signals
input ENUM_TIMEFRAMES InpFilterTimeframe = PERIOD_H4;  // Timeframe for the MACD trend filter

input group "--- Entry Signal Settings ---"
input double InpRsiTriggerSell = 70.0; // RSI level to signal a sell
input double InpRsiTriggerBuy  = 30.0; // RSI level to signal a buy
input double InpStochTriggerSell = 80.0; // Stochastic level to signal a sell
input double InpStochTriggerBuy  = 20.0; // Stochastic level to signal a buy
input ENUM_MACD_FILTER_MODE InpMacdFilterMode = FILTER_TREND; // How to use the MACD filter

input group "--- RSI Settings ---"
input int    InpRsiPeriods = 14;          // RSI period
input ENUM_APPLIED_PRICE InpRsiAppPrice = PRICE_CLOSE; // RSI applied price

input group "--- Stochastic Settings ---"
input int    InpStochK        = 5;       // Stochastic %K period
input int    InpStochD        = 3;       // Stochastic %D period
input int    InpStochSlowing  = 3;       // Stochastic slowing value
input ENUM_MA_METHOD InpStochMaMethod = MODE_SMA; // Stochastic MA method
input ENUM_STO_PRICE InpStochPriceField = STO_LOWHIGH; // Stochastic price field

input group "--- MACD Settings ---"
input int    InpMacdFastPeriod   = 12;      // MACD Fast EMA period
input int    InpMacdSlowPeriod   = 26;      // MACD Slow EMA period
input int    InpMacdSignalPeriod = 9;       // MACD Signal SMA period
input ENUM_APPLIED_PRICE InpMacdAppPrice = PRICE_CLOSE; // MACD applied price

//--- GLOBAL VARIABLES
CTrade trade;
int    g_handleRsi   = INVALID_HANDLE;
int    g_handleStoch = INVALID_HANDLE;
int    g_handleMacd  = INVALID_HANDLE;
datetime g_lastBarTime = 0;

// Indicator buffers
double g_rsiVal;
double g_stochVal;
double g_macdMain;
double g_macdSignal;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("--- Initializing Oscillator EA v", _MQL5InfoString(MQL5_VERSION), " ---");

   //--- Initialize indicator handles
   g_handleRsi = iRSI(_Symbol, InpSignalTimeframe, InpRsiPeriods, InpRsiAppPrice);
   if(g_handleRsi == INVALID_HANDLE)
   {
      Print("Error initializing RSI indicator. Error code: ", GetLastError());
      return(INIT_FAILED);
   }

   g_handleStoch = iStochastic(_Symbol, InpSignalTimeframe, InpStochK, InpStochD, InpStochSlowing, InpStochMaMethod, InpStochPriceField);
   if(g_handleStoch == INVALID_HANDLE)
   {
      Print("Error initializing Stochastic indicator. Error code: ", GetLastError());
      return(INIT_FAILED);
   }

   if(InpMacdFilterMode != FILTER_DISABLED)
   {
      g_handleMacd = iMACD(_Symbol, InpFilterTimeframe, InpMacdFastPeriod, InpMacdSlowPeriod, InpMacdSignalPeriod, InpMacdAppPrice);
      if(g_handleMacd == INVALID_HANDLE)
      {
         Print("Error initializing MACD indicator. Error code: ", GetLastError());
         return(INIT_FAILED);
      }
   }

   //--- Setup trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode(); // Use account's default margin mode
   trade.SetTypeFillingBySymbol(_Symbol); // Use symbol's default filling type

   Print("--- Initialization successful ---");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("--- Deinitializing Oscillator EA. Reason: ", reason, " ---");

   //--- Release indicator handles
   if(g_handleRsi != INVALID_HANDLE)
      IndicatorRelease(g_handleRsi);
   if(g_handleStoch != INVALID_HANDLE)
      IndicatorRelease(g_handleStoch);
   if(g_handleMacd != INVALID_HANDLE)
      IndicatorRelease(g_handleMacd);

   Print("--- Deinitialization complete ---");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Only run logic on a new bar to conserve resources
   if(!IsNewBar())
      return;

   //--- Get the latest indicator values
   if(!GetIndicatorValues())
      return; // Stop if we can't get indicator data

   //--- Manage any open positions (e.g., trailing stop)
   ManageOpenTrades();

   //--- If a trade is already open, don't look for new signals
   if(IsTradeOpen())
      return;

   //--- Check for new trade signals
   CheckTradeSignals();
}

//+------------------------------------------------------------------+
//| Checks if a new bar has started                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = (datetime)iTime(_Symbol, InpSignalTimeframe, 0);
   if(g_lastBarTime < currentBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Retrieves latest values from all indicators                      |
//+------------------------------------------------------------------+
bool GetIndicatorValues()
{
   //--- RSI
   double rsiBuffer[];
   if(CopyBuffer(g_handleRsi, 0, 1, 1, rsiBuffer) != 1)
   {
      Print("Error copying RSI buffer. Error code: ", GetLastError());
      return false;
   }
   g_rsiVal = rsiBuffer[0];

   //--- Stochastic
   double stochBuffer[];
   if(CopyBuffer(g_handleStoch, 0, 1, 1, stochBuffer) != 1)
   {
      Print("Error copying Stochastic buffer. Error code: ", GetLastError());
      return false;
   }
   g_stochVal = stochBuffer[0];

   //--- MACD (if enabled)
   if(InpMacdFilterMode != FILTER_DISABLED)
   {
      double macdMainBuffer[], macdSignalBuffer[];
      if(CopyBuffer(g_handleMacd, 0, 1, 1, macdMainBuffer) != 1 || CopyBuffer(g_handleMacd, 1, 1, 1, macdSignalBuffer) != 1)
      {
         Print("Error copying MACD buffers. Error code: ", GetLastError());
         return false;
      }
      g_macdMain = macdMainBuffer[0];
      g_macdSignal = macdSignalBuffer[0];
   }

   return true;
}

//+------------------------------------------------------------------+
//| Manages trailing stop for any open position                      |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   //--- Only manage trades if trailing stop is enabled
   if(InpTslPercent <= 0 || InpTslTriggerPercent <= 0)
      return;

   // Loop backwards as we might be closing positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         //--- Check if the position belongs to this EA instance
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSl = PositionGetDouble(POSITION_SL);
            double currentTp = PositionGetDouble(POSITION_TP);
            double newSl = currentSl;

            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               //--- Check if trailing stop should be triggered
               if(bid > openPrice + (openPrice * InpTslTriggerPercent / 100.0))
               {
                  //--- Calculate new stop loss
                  double potentialSl = bid - (bid * InpTslPercent / 100.0);
                  //--- We only move the stop loss up
                  if(potentialSl > currentSl)
                  {
                     newSl = potentialSl;
                  }
               }
            }
            else // It's a SELL position
            {
               double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               //--- Check if trailing stop should be triggered
               if(ask < openPrice - (openPrice * InpTslTriggerPercent / 100.0))
               {
                  //--- Calculate new stop loss
                  double potentialSl = ask + (ask * InpTslPercent / 100.0);
                  //--- We only move the stop loss down
                  if(potentialSl < currentSl || currentSl == 0)
                  {
                     newSl = potentialSl;
                  }
               }
            }

            //--- If the new stop loss is different, modify the position
            if(newSl != currentSl)
            {
               if(!trade.PositionModify(ticket, newSl, currentTp))
               {
                  Print("Error modifying position #", ticket, " to set new SL. Error: ", trade.ResultComment());
               }
               else
               {
                  Print("Position #", ticket, " SL trailed to ", DoubleToString(newSl, _Digits));
               }
            }
         }
      }
   }
}


//+------------------------------------------------------------------+
//| Checks if a trade managed by this EA is currently open           |
//+------------------------------------------------------------------+
bool IsTradeOpen()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) // Select position by ticket
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            return true; // Found a trade from this EA
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Checks for market conditions to open a new trade                 |
//+------------------------------------------------------------------+
void CheckTradeSignals()
{
   //--- MACD Filter Check
   bool macdBuyFilter = (InpMacdFilterMode == FILTER_DISABLED) || (g_macdMain > g_macdSignal);
   bool macdSellFilter = (InpMacdFilterMode == FILTER_DISABLED) || (g_macdMain < g_macdSignal);

   //--- Check for BUY signal
   if(g_rsiVal < InpRsiTriggerBuy && g_stochVal < InpStochTriggerBuy && macdBuyFilter)
   {
      OpenTrade(ORDER_TYPE_BUY);
      return; // Exit after opening a trade
   }

   //--- Check for SELL signal
   if(g_rsiVal > InpRsiTriggerSell && g_stochVal > InpStochTriggerSell && macdSellFilter)
   {
      OpenTrade(ORDER_TYPE_SELL);
      return; // Exit after opening a trade
   }
}

//+------------------------------------------------------------------+
//| Opens a new trade with calculated SL and TP                      |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type)
{
   double price = 0;
   double sl = 0;
   double tp = 0;

   if(type == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(InpSlPercent > 0)
         sl = price - (price * InpSlPercent / 100.0);
      if(InpTpPercent > 0)
         tp = price + (price * InpTpPercent / 100.0);

      if(!trade.Buy(InpLots, _Symbol, price, sl, tp, InpEaComment))
      {
         Print("Buy order failed. Error: ", trade.ResultComment());
      }
      else
      {
         Print("Buy order placed successfully. Ticket #", trade.ResultOrder());
      }
   }
   else if(type == ORDER_TYPE_SELL)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(InpSlPercent > 0)
         sl = price + (price * InpSlPercent / 100.0);
      if(InpTpPercent > 0)
         tp = price - (price * InpTpPercent / 100.0);

      if(!trade.Sell(InpLots, _Symbol, price, sl, tp, InpEaComment))
      {
         Print("Sell order failed. Error: ", trade.ResultComment());
      }
      else
      {
         Print("Sell order placed successfully. Ticket #", trade.ResultOrder());
      }
   }
}
