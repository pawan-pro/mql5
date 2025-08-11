
#property copyright "Copyright 2024, QuantWater Tech Investments"
#property link      "https://www.TBU.com"
#property version   "1.00"
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
input ENUM_TIMEFRAMES Timeframe = PERIOD_H1;
input ENUM_TIMEFRAMES FilterTimeFrame = PERIOD_H4;
input double RsiTriggerSell = 70;
input double RsiTriggerBuy = 30;
input double StochTriggerSell = 70;
input double StochTriggerBuy = 30;
input bool IsFilterMacd = false;
//The trades are not closed by MACD

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

input group "Prop Settings - Max Daily Loss & Drawdown"
double initialAccountBalance;
double maxTotalLoss;
double maxDailyLoss;
double dailyLoss = 0.0;
double totalLoss = 0.0;
datetime lastDayChecked = 0;
MqlDateTime currentTime;
MqlDateTime lastDay;



int handleRsi; //Global variable of type int, followed by name. declaration of variable
int handleStoch;
int handleMacd;

//RAM of your PC
//reserve 8 byte
//int has no decimal
//double has decimals

CTrade trade;

int barsTotal;
ulong posTicket; //number without decimal; bigger. More RAM required

int OnInit(){
   TimeToStruct(TimeTradeServer(),lastDay);
   initialAccountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   maxDailyLoss = initialAccountBalance * 0.05; //5% of the initial account balance
   maxTotalLoss = initialAccountBalance * 0.1; //10% of the initial account balance

   handleRsi = iRSI(_Symbol,Timeframe,RsiPeriods,RsiAppPrice);
   handleStoch = iStochastic(_Symbol,Timeframe,Stochk,StochD,StochSlowing,StochMaMethod,StochPriceField);
   handleMacd = iMACD(_Symbol,FilterTimeFrame,MacdFastPeriod,MacdSlowPeriod,MacdSignalPeriod,MacdAppPrice);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){

}

void OnTick(){
  //Reset daily loss if new day
    TimeToStruct(TimeTradeServer(),currentTime);
    if(currentTime.day_of_year != lastDay.day_of_year){
         lastDay = currentTime;
         dailyLoss = 0.0;
    }

  //Check for daily loss & total loss limits
  double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
  dailyLoss = initialAccountBalance - currentBalance; //daily loss
  totalLoss = initialAccountBalance - currentBalance; //total loss

  if(dailyLoss > maxDailyLoss || totalLoss > maxTotalLoss){
      Print("Daily Loss: ", dailyLoss, " Total Loss: ", totalLoss);
      Print("Max Daily Loss: ", maxDailyLoss, " Max Total Loss: ", maxTotalLoss);
      Print("Exiting the EA due to daily or total loss limits");
      ExpertRemove(); //exit OnTick to prevent further trading
  }




  int bars = iBars(_Symbol,FilterTimeFrame);
  if(barsTotal != bars){
     barsTotal = bars;

        double rsi[]; //dynamic array >> size changes with int_const

        CopyBuffer(handleRsi,MAIN_LINE,1,1,rsi);

        double stoch[]; //dynamic array >> size changes with int_const

        CopyBuffer(handleStoch,MAIN_LINE,1,1,stoch);

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
           if(rsi[0] > RsiTriggerSell){
               if(stoch[0] > StochTriggerSell){
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
               }
           }
          }
          if(rsi[0] < RsiTriggerBuy){
               if(stoch[0] < StochTriggerBuy){
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
                  }
               }
  }
      // Ensure to update dailyLoss with the result of closed trades
        dailyLoss = initialAccountBalance - AccountInfoDouble(ACCOUNT_BALANCE);
        totalLoss = initialAccountBalance - AccountInfoDouble(ACCOUNT_BALANCE);
        profit = AccountInfoDouble(ACCOUNT_PROFIT);
        loss    = AccountInfoDouble(ACCOUNT_LOSS);
        Print("Daily Loss: ", dailyLoss, " Total Loss: ", totalLoss);
        Print("Profit: ", profit, " Loss: ", loss);
        Print("Max Daily Loss: ", maxDailyLoss, " Max Total Loss: ", maxTotalLoss);
    }

      //You need to adjust where and how you calculate dailyLoss and totalLoss based on your specific trading strategy
      //and accounting for profits/losses from closed trades within the trading day or the entire trading period.
      //TBU: bal - equity - tick - total - daily

}
}
