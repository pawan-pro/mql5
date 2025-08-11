
#property copyright "Copyright 2024, QuantWater Tech Investments"
#property link      "https://www.TBU.com"
#property version   "3.00"
#property strict
#property description "This is an Oscillator Expert Advisor"

#include <Trade/Trade.mqh>

input group "Trade Settings"
input double Lots = 0.1;
input double TpPercent = 1.0;
// 1.0% of the current price of symbol
input double SlPercent = 0.5;
input double TslTrigger = 0.2;
input double TslTriggerPercent = 0.5;


input group "General Settings"
//input ENUM_TIMEFRAMES Timeframe = PERIOD_H1;
input ENUM_TIMEFRAMES FilterTimeFrame = PERIOD_H4;
//input double RsiTriggerSell = 70;
//input double RsiTriggerBuy = 30;
//input double StochTriggerSell = 70;
//input double StochTriggerBuy = 30;
input bool IsFilterMacd = false;
//The trades are not closed by MACD

input group "RSI Settings"
//input int RsiPeriods = 14;
//input ENUM_APPLIED_PRICE RsiAppPrice = PRICE_CLOSE;

//

input group "MACD Settings"
input int MacdFastPeriod = 12;
input int MacdSlowPeriod = 26;
input int MacdSignalPeriod = 9;
input ENUM_APPLIED_PRICE MacdAppPrice = PRICE_CLOSE ;

//int handleRsi; //Global variable of type int, followed by name. declaration of variable
//int handleStoch;
int handleMacd;

//RAM of your PC
//reserve 8 byte
//int has no decimal
//double has decimals

CTrade trade;

int barsTotal;
ulong posTicket; //number without decimal; bigger. More RAM required

int OnInit(){
//   handleRsi = iRSI(_Symbol,Timeframe,RsiPeriods,RsiAppPrice);
//   handleStoch = iStochastic(_Symbol,Timeframe,Stochk,StochD,StochSlowing,StochMaMethod,StochPriceField);
   handleMacd = iMACD(_Symbol,FilterTimeFrame,MacdFastPeriod,MacdSlowPeriod,MacdSignalPeriod,MacdAppPrice);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){

}

void OnTick(){
  int bars = iBars(_Symbol,FilterTimeFrame);
  if(barsTotal != bars){
     barsTotal = bars;

    //    double rsi[]; //dynamic array >> size changes with int_const

    //    CopyBuffer(handleRsi,MAIN_LINE,1,1,rsi);

    //    double stoch[]; //dynamic array >> size changes with int_const

    //    CopyBuffer(handleStoch,MAIN_LINE,1,1,stoch);

        //Print(stoch[0]);

        double MacdMain[], MacdSignal[] ; //dynamic array >> size changes with int_const

        CopyBuffer(handleMacd,MAIN_LINE,1,1,MacdMain);
        CopyBuffer(handleMacd,SIGNAL_LINE,1,1,MacdSignal);


        double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
        double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

        if(posTicket > 0){
         if(PositionSelectByTicket(posTicket)){
            double posPriceOpen = PositionGetDouble(POSITION_PRICE_OPEN);
            double posTp = PositionGetDouble(POSITION_TP);
            double posSl = PositionGetDouble(POSITION_SL);


            if(PositionGetInteger(POSITION_TYPE)== POSITION_TYPE_BUY){
               if(IsFilterMacd){
                  if(MacdMain[0] < MacdSignal[0]){
                     if(trade.PositionClose(posTicket)){
                        Print(__FUNCTION__," > Pos #",posTicket, " was closed because of macd...");
                        posTicket = 0;
                     }
               }
               }
               if(TslTriggerPercent > 0){
                  if(bid > posPriceOpen + posPriceOpen*TslTriggerPercent/100 ){
                     double sl = bid - bid*TslTriggerPercent/100;

                     if(sl > posSl){
                        if(trade.PositionModify(posTicket,sl,posTp)){
                        }
                     }
                  }
               }

            } else if(PositionGetInteger(POSITION_TYPE)== POSITION_TYPE_SELL){
               if(IsFilterMacd){
                  if(MacdMain[0] > MacdSignal[0]){
                     if(trade.PositionClose(posTicket)){
                        Print(__FUNCTION__," > Pos #",posTicket, " was closed because of macd...");
                        posTicket = 0;
                     }
               }
               }
               if(TslTriggerPercent > 0){
                  if(ask < posPriceOpen - posPriceOpen*TslTriggerPercent/100 ){
                     double sl = ask + ask*TslTriggerPercent/100;

                     if(sl < posSl || posSl == 0){
                        if(trade.PositionModify(posTicket,sl,posTp)){
                        }
                     }
                  }
               }
            }

         } else{
            Print(__FUNCTION__," > Pos #",posTicket, " was closed...");
            posTicket = 0;
         }
        }

        if(posTicket <= 0){
        //   if(rsi[0] > RsiTriggerSell){
        //       if(stoch[0] > StochTriggerSell){
                  if(MacdMain[0] < MacdSignal[0]){
                     Print("Sell"); //body executed if condition is true

                     double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
                     double tp = 0;
                     if(TpPercent > 0) tp = entry - entry*TpPercent/100;
                     double sl = 0;
                     if(SlPercent > 0) sl = entry + entry*SlPercent/100;

                     if(trade.Sell(Lots,_Symbol,entry,sl,tp));{
                        posTicket = trade.ResultOrder();
                        Print(__FUNCTION__," > Pos #",posTicket," was executed...");
                     }
                  }
            //   }
           //}
          }
          //if(rsi[0] < RsiTriggerBuy){
          //     if(stoch[0] < StochTriggerBuy){
                  if(MacdMain[0] > MacdSignal[0]){
                     Print("Buy"); //body executed if condition is true

                     double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

                     double tp = 0;
                     if(TpPercent > 0) tp = entry + entry*TpPercent/100;

                     double sl = 0;
                     if(SlPercent > 0) sl = entry - entry*SlPercent/100;


                     if(trade.Buy(Lots,_Symbol,entry,sl,tp));{
                        posTicket = trade.ResultOrder();
                        Print(__FUNCTION__," > Pos #",posTicket," was executed...");
                     }
            //      }
            //   }
  }
}
}
