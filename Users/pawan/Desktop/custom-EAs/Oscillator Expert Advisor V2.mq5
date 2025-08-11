#property copyright "Copyright 2024, QuantWater Tech Investments"

#property link      "https://www.TBU.com"

#property version   "2.00"

#property strict

#property description "This is an Oscillator Expert Advisor"



#include <Trade/Trade.mqh>



input group "Trade Settings"

input double Lots = 0.1;

input double TpPercent = 1.0;

input double SlPercent = 0.5;

input double TslTrigger = 0.2;

input double TslTriggerPercent = 0.5;



input group "General Settings"

input ENUM_TIMEFRAMES Timeframe = PERIOD_H1;

input ENUM_TIMEFRAMES FilterTimeFrame = PERIOD_H4;

input double RsiTriggerSell = 70;

input double RsiTriggerBuy = 30;

input double StochTriggerSell = 70;

input double StochTriggerBuy = 30;

input bool IsFilterRsi = false;

input bool IsFilterStoch = false;

input bool IsFilterMacd = false;



input group "RSI Settings"

input int RsiPeriods = 14;

input ENUM_APPLIED_PRICE RsiAppPrice = PRICE_CLOSE;



input group "Stoch Settings"

input int Stochk = 5;

input int StochD = 3;

input int StochSlowing = 3;

input ENUM_MA_METHOD StochMaMethod = MODE_SMA;

input ENUM_STO_PRICE StochPriceField = STO_LOWHIGH;



input group "MACD Settings"

input int MacdFastPeriod = 12;

input int MacdSlowPeriod = 26;

input int MacdSignalPeriod = 9;

input ENUM_APPLIED_PRICE MacdAppPrice = PRICE_CLOSE ;



int handleRsi;

int handleStoch;

int handleMacd;



CTrade trade;



int barsTotal;

ulong posTicket;



int OnInit(){

   handleRsi = iRSI(_Symbol,Timeframe,RsiPeriods,RsiAppPrice);

   handleStoch = iStochastic(_Symbol,Timeframe,Stochk,StochD,StochSlowing,StochMaMethod,StochPriceField);

   handleMacd = iMACD(_Symbol,FilterTimeFrame,MacdFastPeriod,MacdSlowPeriod,MacdSignalPeriod,MacdAppPrice);



   return(INIT_SUCCEEDED);

}



void OnDeinit(const int reason){



}



void OnTick(){

    int bars = iBars(_Symbol,FilterTimeFrame);

    if(barsTotal != bars){

        barsTotal = bars;



            double rsi[];

            CopyBuffer(handleRsi,MAIN_LINE,1,1,rsi);



            double stoch[];

            CopyBuffer(handleStoch,MAIN_LINE,1,1,stoch);



            double MacdMain[], MacdSignal[] ;

            CopyBuffer(handleMacd,MAIN_LINE,1,1,MacdMain);

            CopyBuffer(handleMacd,SIGNAL_LINE,1,1,MacdSignal);



            double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);

            double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);



            if(posTicket > 0){

                // Existing position management code

                if (PositionSelectByTicket(posTicket)) {

                    bool rsiSellCondition = rsi[0] > RsiTriggerSell;

                    bool stochSellCondition = stoch[0] > StochTriggerSell;

                    bool macdSellCondition = MacdMain[0] < MacdSignal[0];



                    bool rsiBuyCondition = rsi[0] < RsiTriggerBuy;

                    bool stochBuyCondition = stoch[0] < StochTriggerBuy;

                    bool macdBuyCondition = MacdMain[0] > MacdSignal[0];



                if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && ((IsFilterRsi && rsiSellCondition) || (IsFilterStoch && stochSellCondition) || (IsFilterMacd && macdSellCondition))){

                    trade.PositionClose(posTicket);

                }

                if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && ((IsFilterRsi && rsiBuyCondition) || (IsFilterStoch && stochBuyCondition) || (IsFilterMacd && macdBuyCondition))){

                    trade.PositionClose(posTicket);

                }

            }





            if(posTicket <= 0){

                bool rsiSellCondition = rsi[0] > RsiTriggerSell;

                bool stochSellCondition = stoch[0] > StochTriggerSell;

                bool macdSellCondition = MacdMain[0] < MacdSignal[0];



                bool rsiBuyCondition = rsi[0] < RsiTriggerBuy;

                bool stochBuyCondition = stoch[0] < StochTriggerBuy;

                bool macdBuyCondition = MacdMain[0] > MacdSignal[0];



                if((IsFilterRsi && rsiSellCondition) || (IsFilterStoch && stochSellCondition) || (IsFilterMacd && macdSellCondition)){

                    // Sell order code

                    double sl = bid + SlPercent * bid;

                    double tp = bid - TpPercent * bid;

                    trade.Sell(Lots, bid, sl, tp);

                }

                if((IsFilterRsi && rsiBuyCondition) || (IsFilterStoch && stochBuyCondition) || (IsFilterMacd && macdBuyCondition)){

                    // Buy order code

                    double sl = ask - SlPercent * ask;

                    double tp = ask + TpPercent * ask;

                    trade.Buy(Lots, ask, sl, tp);

                }

            }

        }

    }

}