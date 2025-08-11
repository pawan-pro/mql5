//+------------------------------------------------------------------+
//|                                      SignalProcessor_Portfolio.mq5 |
//|            Copyright 2024, Professionally Refactored by Jules |
//|                                      https://www.mql5.com/en/users/jules |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Professionally Refactored by Jules"
#property link      "https://www.mql5.com"
#property version   "7.00" // Professional Portfolio Version
#property description "A professional-grade trade execution utility that reads signals from a CSV file."
#property description "Features include: dynamic risk management, two-scenario signal processing,"
#property description "automatic scenario switching, and comprehensive pre-trade safety checks."

#include <Trade\Trade.mqh>

//--- EA INPUT PARAMETERS ---

input group           "--- Core Settings ---"
input ulong           InpMagicNumber = 67890;         // Unique Magic Number for this EA instance
input string          InpEaComment = "SignalProcessor"; // Custom comment for trades
input string          InpSignalFileName = "signals.csv"; // CSV file name (in MQL5/Files or Common/Files)
input int             InpTimerFrequency = 5;            // How often to check the signal file (seconds)

input group           "--- Risk Management ---"
input double          InpFixedPercentageRisk = 1.0;     // Risk per trade as % of account balance
input double          InpMinimumAcceptableRRR = 1.5;    // Minimum Risk-to-Reward Ratio required to trade

input group           "--- Entry Logic ---"
input bool            InpWaitForEntryPrice = true;      // Wait for market to reach the signal's entry price?
input bool            InpEnableScenarioSwitch = true;   // Automatically switch to the alternative scenario if price moves against the primary one?
input double          InpEntryTolerancePips = 5.0;      // Entry tolerance in pips (if ATR fails)
input int             InpAtrPeriod = 14;                // ATR period for dynamic entry tolerance
input double          InpEntryToleranceATR_Percent = 0.25; // Dynamic tolerance as % of ATR value
input double          InpMaxEntryTolerancePips = 25.0;  // Maximum cap for dynamic entry tolerance (in pips)

input group           "--- Execution & Safety ---"
input double          InpSpreadMultiplierForStop = 2.0; // Minimum stop distance in multiples of spread
input uint            InpSlippage = 10;                 // Allowed slippage in points

input group           "--- Debug & Logging ---"
input bool            InpEnableDebugMode = true;        // Enable detailed debug logging in the Experts tab
input bool            InpLogFileContents = false;       // Log entire file contents (for debugging parsing issues)
input bool            InpEnableTradingStatusCheck = true; // Enable periodic checks of trading permissions


//--- DATA STRUCTURES ---

// This structure holds the data for a single pending trade signal, including
// both the primary and alternative scenarios. It is the core of the EA's logic,
// allowing it to monitor and react to market changes dynamically.
struct PendingSignal
{
   string   symbol;                  // Symbol (e.g., "EURUSD")
   string   current_action;          // Current active action ("Buy" or "Sell")
   double   current_entry;           // Current entry price to monitor
   double   current_target;          // Current take profit
   double   current_stop_loss;       // Current stop loss
   string   alt_action;              // Alternative scenario's action
   double   alt_entry;               // Alternative scenario's entry price
   double   alt_target;              // Alternative scenario's take profit
   datetime signal_time;             // Timestamp when the signal was processed
   bool     scenario_one_active;     // True if the primary scenario is active, false if switched to alternative
   double   scenario_switch_price;   // The price that triggers the switch from primary to alternative (usually the alternative entry price)

   // Copy constructor for safe assignments
   PendingSignal(const PendingSignal &other)
   {
      symbol = other.symbol;
      current_action = other.current_action;
      current_entry = other.current_entry;
      current_target = other.current_target;
      current_stop_loss = other.current_stop_loss;
      alt_action = other.alt_action;
      alt_entry = other.alt_entry;
      alt_target = other.alt_target;
      signal_time = other.signal_time;
      scenario_one_active = other.scenario_one_active;
      scenario_switch_price = other.scenario_switch_price;
   }

   // Default constructor (required for arrays)
   PendingSignal()
   {
      symbol = "";
      current_action = "";
      current_entry = 0.0;
      current_target = 0.0;
      current_stop_loss = 0.0;
      alt_action = "";
      alt_entry = 0.0;
      alt_target = 0.0;
      signal_time = 0;
      scenario_one_active = true;
      scenario_switch_price = 0.0;
   }
};


//--- GLOBAL VARIABLES ---
CTrade            trade;
long              g_lastFileModifyTime = 0;
int               g_debugCounter = 0;
PendingSignal     g_pending_signals[];
int               g_pending_count = 0;
datetime          g_lastStatusCheck = 0;


//+------------------------------------------------------------------+
//| Custom Debug Print Function                                      |
//+------------------------------------------------------------------+
void DebugPrint(string message)
{
   if(InpEnableDebugMode)
   {
      Print("[DEBUG-", g_debugCounter++, "] ", TimeCurrent(), " | ", message);
   }
}

//+------------------------------------------------------------------+
//| Checks all trading permissions (terminal, expert, account)       |
//+------------------------------------------------------------------+
bool CheckTradingPermissions(bool print_details = false)
{
   bool terminalTradeAllowed = TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool expertTradeAllowed = MQLInfoInteger(MQL_TRADE_ALLOWED);
   bool accountTradeAllowed = AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);

   if(print_details)
   {
      DebugPrint("=== TRADING PERMISSIONS CHECK ===");
      DebugPrint("Terminal AutoTrading Button: " + (terminalTradeAllowed ? "ON" : "OFF"));
      DebugPrint("EA Settings 'Allow Algo Trading': " + (expertTradeAllowed ? "ON" : "OFF"));
      DebugPrint("Account Trading Enabled: " + (accountTradeAllowed ? "YES" : "NO"));
      DebugPrint("Terminal Connected to Server: " + (TerminalInfoInteger(TERMINAL_CONNECTED) ? "YES" : "NO"));
   }

   bool allPermissionsOK = terminalTradeAllowed && expertTradeAllowed && accountTradeAllowed;
   if(!allPermissionsOK && print_details)
   {
      Print(InpEaComment, ": *** CRITICAL TRADING PERMISSION ISSUE ***");
      if(!terminalTradeAllowed)
         Print(InpEaComment, ": >>> FIX: Enable 'Algo Trading' button in the MetaTrader toolbar.");
      if(!expertTradeAllowed)
         Print(InpEaComment, ": >>> FIX: In EA properties, go to 'Common' tab and check 'Allow Algo Trading'.");
      if(!accountTradeAllowed)
         Print(InpEaComment, ": >>> FIX: Contact your broker. Trading is disabled on this account.");
   }
   return allPermissionsOK;
}

//+------------------------------------------------------------------+
//| Checks if a specific symbol is available and tradable            |
//+------------------------------------------------------------------+
bool CheckSymbolTradingStatus(string symbol, bool print_details = false)
{
   if(!SymbolSelect(symbol, true))
   {
      if(print_details) DebugPrint("Failed to select symbol '" + symbol + "' in Market Watch.");
      return false;
   }

   long tradeMode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   bool tradingAllowed = (tradeMode == SYMBOL_TRADE_MODE_FULL);

   if(print_details)
   {
      DebugPrint("Symbol " + symbol + " trade mode: " + EnumToString((ENUM_SYMBOL_TRADE_MODE)tradeMode));
      if(!tradingAllowed)
      {
         Print(InpEaComment, ": *** WARNING: Trading for symbol '", symbol, "' is not fully enabled. Mode: ", EnumToString((ENUM_SYMBOL_TRADE_MODE)tradeMode), " ***");
      }
   }
   return tradingAllowed;
}

//+------------------------------------------------------------------+
//| Periodically monitors the overall trading status                 |
//+------------------------------------------------------------------+
void MonitorTradingStatus()
{
   if(!InpEnableTradingStatusCheck) return;

   if(TimeCurrent() - g_lastStatusCheck > 300) // Check every 5 minutes
   {
      DebugPrint("--- Performing periodic trading status check ---");
      if(!CheckTradingPermissions(true))
      {
         Print(InpEaComment, ": *** WARNING: Periodic check failed. Trading will not be possible until permissions are fixed. ***");
      }
      else
      {
         DebugPrint("Periodic check: Trading permissions are OK.");
      }
      g_lastStatusCheck = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== Initializing ", InpEaComment, " v", _MQL5InfoString(MQL5_VERSION), " ===");
   Print("Magic Number: ", InpMagicNumber, " | Signal File: '", InpSignalFileName, "'");

   //--- Setup CTrade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(InpSlippage);

   //--- Perform initial, detailed check of trading environment
   Print("--- Performing initial trading environment check... ---");
   if(!CheckTradingPermissions(true))
   {
      Print(InpEaComment, ": *** CRITICAL WARNING: Trading permissions are not correctly set. EA cannot execute trades. ***");
   }
   else
   {
      Print(InpEaComment, ": *** Trading permissions OK. Ready to process signals. ***");
   }

   //--- Set up the timer to check the signal file
   EventSetTimer(InpTimerFrequency);
   Print("--- Initialization Complete. Timer set to ", InpTimerFrequency, " seconds. ---");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   string reasonText;
   // Provide clear text for deinitialization reason
   switch(reason)
   {
      case REASON_PROGRAM:   reasonText = "EA terminated programmatically"; break;
      case REASON_REMOVE:    reasonText = "EA removed from chart"; break;
      case REASON_RECOMPILE: reasonText = "EA recompiled"; break;
      case REASON_CHARTCHANGE: reasonText = "Chart symbol or period changed"; break;
      case REASON_CHARTCLOSE:  reasonText = "Chart closed"; break;
      case REASON_PARAMETERS:reasonText = "Input parameters changed"; break;
      case REASON_ACCOUNT:   reasonText = "Account changed"; break;
      case REASON_TEMPLATE:  reasonText = "New template applied"; break;
      case REASON_INITFAILED:reasonText = "Initialization failed"; break;
      case REASON_CLOSE:     reasonText = "Terminal closed"; break;
      default:               reasonText = "Unknown reason";
   }
   Print(InpEaComment, ": Deinitializing. Reason: ", reasonText);
}

//+------------------------------------------------------------------+
//| OnTick Function - Monitors entry conditions for pending signals  |
//+------------------------------------------------------------------+
void OnTick()
{
   // OnTick is used only to monitor for the exact entry price of pending signals.
   // The main logic for file checking is in OnTimer to be more efficient.
   if(g_pending_count == 0) return; // No signals to check, do nothing.

   // Loop backwards because a signal might be removed if a trade is executed
   for(int i = g_pending_count - 1; i >= 0; i--)
   {
      CheckEntryConditions(i);
   }
}

//+------------------------------------------------------------------+
//| Timer Function - Main logic loop for checking the signal file    |
//+------------------------------------------------------------------+
void OnTimer()
{
   DebugPrint("Timer triggered. Checking signal file and system status.");
   MonitorTradingStatus(); // Periodically check trading permissions

   // Check if the signal file exists in the correct directory (MQL5/Files or Common/Files)
   if(!FileIsExist(InpSignalFileName, FILE_COMMON))
   {
      DebugPrint("Signal file '", InpSignalFileName, "' not found in MQL5/Files or Common/Files folder.");
      return;
   }

   // Open file to check its last modification time
   int fileHandle = FileOpen(InpSignalFileName, FILE_READ | FILE_BIN | FILE_COMMON);
   if(fileHandle == INVALID_HANDLE)
   {
      DebugPrint("Failed to open signal file to check timestamp. Error: ", IntegerToString(GetLastError()));
      return;
   }
   long currentModifyTime = FileGetInteger(fileHandle, FILE_MODIFY_DATE);
   FileClose(fileHandle);

   // If the file has been modified since our last check, process it.
   if(currentModifyTime > g_lastFileModifyTime)
   {
      Print(InpEaComment, ": *** New signal file version detected. Processing... ***");
      g_lastFileModifyTime = currentModifyTime;
      ProcessSignals(); // The core function to parse the file and set up pending signals
   }
   else
   {
      DebugPrint("No file changes detected.");
   }
}


//+------------------------------------------------------------------+
//| Checks market conditions against a specific pending signal       |
//+------------------------------------------------------------------+
void CheckEntryConditions(int signal_index)
{
   if(signal_index >= g_pending_count) return;

   PendingSignal sig = g_pending_signals[signal_index];
   MqlTick tick;
   if(!SymbolInfoTick(sig.symbol, tick)) return; // Can't get price, can't do anything

   double current_market_price = (sig.current_action == "Buy") ? tick.ask : tick.bid;

   // --- SCENARIO SWITCHING LOGIC ---
   // If enabled, check if the market has moved against the primary signal and crossed the threshold for the alternative signal.
   if(InpEnableScenarioSwitch && sig.scenario_one_active)
   {
      bool should_switch = false;
      // For a BUY signal, if price drops BELOW the switch price, we activate the alternative (SELL)
      if(sig.current_action == "Buy" && current_market_price < sig.scenario_switch_price)
         should_switch = true;
      // For a SELL signal, if price rises ABOVE the switch price, we activate the alternative (BUY)
      else if(sig.current_action == "Sell" && current_market_price > sig.scenario_switch_price)
         should_switch = true;

      if(should_switch)
      {
         Print(InpEaComment, ": *** SCENARIO SWITCH TRIGGERED for ", sig.symbol, " ***");
         Print("Market price ", DoubleToString(current_market_price, _Digits), " crossed switch level ", DoubleToString(sig.scenario_switch_price, _Digits));

         // Update the pending signal in our global array to reflect the new, active scenario
         g_pending_signals[signal_index].current_action = sig.alt_action;
         g_pending_signals[signal_index].current_entry = sig.alt_entry;
         g_pending_signals[signal_index].current_target = sig.alt_target;
         // The new stop loss is the original scenario's entry, creating a logical reversal point
         g_pending_signals[signal_index].current_stop_loss = sig.current_entry;
         g_pending_signals[signal_index].scenario_one_active = false; // Mark that we have switched

         Print("Switched to Alternative Scenario: ", sig.alt_action, " at ", DoubleToString(sig.alt_entry, _Digits));
         return; // Wait for the next tick to check entry conditions for this new alternative signal
      }
   }

   // --- ENTRY EXECUTION LOGIC ---
   bool execute_trade = false;
   if(!InpWaitForEntryPrice)
   {
      // If we don't wait, execute immediately at market price
      execute_trade = true;
      DebugPrint("Immediate execution mode for " + sig.symbol);
   }
   else
   {
      // Calculate dynamic entry tolerance based on ATR
      double point = SymbolInfoDouble(sig.symbol, SYMBOL_POINT);
      double tolerance = InpEntryTolerancePips * point; // Fallback tolerance
      int atr_handle = iATR(sig.symbol, PERIOD_CURRENT, InpAtrPeriod);
      if(atr_handle != INVALID_HANDLE)
      {
         double atr_buf[];
         if(CopyBuffer(atr_handle, 0, 0, 1, atr_buf) > 0 && atr_buf[0] > 0)
         {
            double dynamic_tol = atr_buf[0] * InpEntryToleranceATR_Percent;
            double cap_tol = InpMaxEntryTolerancePips * point;
            tolerance = MathMin(dynamic_tol, cap_tol); // Use the smaller of dynamic or capped tolerance
         }
         IndicatorRelease(atr_handle);
      }

      // Check if market price is within the tolerance zone of our target entry price
      if(sig.current_action == "Buy")
      {
         execute_trade = (current_market_price <= sig.current_entry + tolerance);
      }
      else // Sell
      {
         execute_trade = (current_market_price >= sig.current_entry - tolerance);
      }

      if(execute_trade)
      {
         DebugPrint("Entry conditions met for " + sig.symbol + ". Target Entry: " + DoubleToString(sig.current_entry, _Digits) + ", Market: " + DoubleToString(current_market_price, _Digits));
      }
   }

   if(execute_trade)
   {
      ExecuteTradeFromSignal(signal_index);
      RemovePendingSignal(signal_index); // Remove from pending list after execution attempt
   }
}

//+------------------------------------------------------------------+
//| Executes a trade based on a validated signal                     |
//+------------------------------------------------------------------+
void ExecuteTradeFromSignal(int signal_index)
{
   if(signal_index >= g_pending_count) return;
   PendingSignal sig = g_pending_signals[signal_index];
   Print(InpEaComment, ": *** ATTEMPTING TO EXECUTE TRADE for ", sig.symbol, " ***");

   // --- COMPREHENSIVE PRE-TRADE SAFETY CHECKS ---
   if(!CheckTradingPermissions(true) || !TerminalInfoInteger(TERMINAL_CONNECTED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !CheckSymbolTradingStatus(sig.symbol, true))
   {
      Print(InpEaComment, ": *** TRADE ABORTED for ", sig.symbol, " due to pre-trade safety check failure. See logs for details. ***");
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(sig.symbol, tick))
   {
      Print(InpEaComment, ": *** TRADE ABORTED for ", sig.symbol, ": Could not retrieve latest price tick. ***");
      return;
   }

   double execution_price = (sig.current_action == "Buy") ? tick.ask : tick.bid;
   double stop_loss = sig.current_stop_loss;
   double take_profit = sig.current_target;

   // --- VALIDATE PRICES AND SPREAD ---
   double spread = tick.ask - tick.bid;
   double min_stop_distance = spread * InpSpreadMultiplierForStop;
   double distance_to_sl = (sig.current_action == "Buy") ? (execution_price - stop_loss) : (stop_loss - execution_price);
   if(distance_to_sl <= min_stop_distance)
   {
      Print(InpEaComment, ": *** TRADE ABORTED for ", sig.symbol, ": Stop loss is too close to entry price relative to current spread. ***");
      return;
   }
   if(stop_loss <= 0 || take_profit <= 0 || execution_price <= 0)
   {
      Print(InpEaComment, ": *** TRADE ABORTED for ", sig.symbol, ": Invalid price data (SL/TP/Entry is zero or negative). ***");
      return;
   }

   // --- CALCULATE AND VALIDATE RISK-REWARD RATIO ---
   double point = SymbolInfoDouble(sig.symbol, SYMBOL_POINT);
   double risk_pips = MathAbs(execution_price - stop_loss) / point;
   double reward_pips = MathAbs(take_profit - execution_price) / point;
   if(risk_pips < 1)
   {
      Print(InpEaComment, ": *** TRADE ABORTED for ", sig.symbol, ": Calculated risk is less than 1 pip. ***");
      return;
   }
   double rrr = (risk_pips > 0) ? reward_pips / risk_pips : 0;
   if(rrr < InpMinimumAcceptableRRR)
   {
      Print(InpEaComment, ": *** TRADE ABORTED for ", sig.symbol, ": RRR (", DoubleToString(rrr, 2), ") is below minimum required (", DoubleToString(InpMinimumAcceptableRRR, 2), "). ***");
      return;
   }

   // --- CLOSE OPPOSITE POSITIONS ---
   // Before opening a new trade, close any existing positions on the same symbol that are in the opposite direction.
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == sig.symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         long pos_type = PositionGetInteger(POSITION_TYPE);
         bool is_buy_pos = (pos_type == POSITION_TYPE_BUY);
         bool signal_is_buy = (sig.current_action == "Buy");
         if(is_buy_pos != signal_is_buy) // If position direction is different from signal direction
         {
            if(trade.PositionClose(ticket))
               Print(InpEaComment, ": Closed opposite position #", (string)ticket, " on ", sig.symbol);
            else
               Print(InpEaComment, ": Failed to close opposite position #", (string)ticket, " on ", sig.symbol, ". Error: ", trade.ResultComment());
         }
      }
   }

   // --- CALCULATE POSITION SIZE ---
   double lot_size = CalculatePositionSize(sig.symbol, stop_loss, risk_pips);
   if(lot_size <= 0)
   {
      Print(InpEaComment, ": *** TRADE ABORTED for ", sig.symbol, ": Position size calculation failed. See debug logs. ***");
      return;
   }

   // --- EXECUTE THE TRADE ---
   Print(InpEaComment, ": --- Final Trade Parameters ---");
   Print("Symbol: ", sig.symbol, " | Action: ", sig.current_action, " | Lots: ", DoubleToString(lot_size, 2));
   Print("Entry: ", DoubleToString(execution_price, _Digits), " | SL: ", DoubleToString(stop_loss, _Digits), " | TP: ", DoubleToString(take_profit, _Digits));
   Print("RRR: ", DoubleToString(rrr, 2), " | Scenario: ", (sig.scenario_one_active ? "Primary" : "Alternative"));

   bool result = false;
   ENUM_ORDER_TYPE order_type = (sig.current_action == "Buy") ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(order_type == ORDER_TYPE_BUY)
      result = trade.Buy(lot_size, sig.symbol, execution_price, stop_loss, take_profit, InpEaComment);
   else
      result = trade.Sell(lot_size, sig.symbol, execution_price, stop_loss, take_profit, InpEaComment);

   // --- REPORTING AND ERROR HANDLING ---
   if(result)
   {
      Print(InpEaComment, ": *** TRADE EXECUTED SUCCESSFULLY for ", sig.symbol, ". Ticket: ", (string)trade.ResultOrder(), " ***");
   }
   else
   {
      Print(InpEaComment, ": *** TRADE FAILED for ", sig.symbol, " ***");
      Print("Error Code: ", (string)trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      Print("Broker Comment: ", trade.ResultComment());
      // Detailed error diagnosis
      switch((int)trade.ResultRetcode())
      {
         case TRADE_RETCODE_INVALID_VOLUME:
            Print(">>> FIX: Calculated lot size ", DoubleToString(lot_size, 2), " is invalid for this symbol. Check Min/Max/Step lot sizes.");
            break;
         case TRADE_RETCODE_INVALID_STOPS:
            Print(">>> FIX: SL or TP is too close to market price. Check symbol's 'Stops Level'.");
            break;
         case TRADE_RETCODE_NO_MONEY:
            Print(">>> FIX: Insufficient margin to execute trade with this lot size.");
            break;
         default:
            Print(">>> See MQL5 documentation for trade server return code ", (string)trade.ResultRetcode());
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Position Size based on Fixed Percentage Risk           |
//+------------------------------------------------------------------+
double CalculatePositionSize(string symbol, double stop_loss, double risk_pips)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * (InpFixedPercentageRisk / 100.0);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tick_value <= 0)
   {
      Print(InpEaComment, ": *** CRITICAL ERROR in ", __FUNCTION__, ": Invalid Tick Value (", DoubleToString(tick_value, 4), ") for symbol ", symbol, ". Ensure symbol is in Market Watch.");
      return 0.0;
   }
   if(risk_pips <= 0)
   {
      DebugPrint("Position sizing for " + symbol + ": Risk pips is zero or negative.");
      return 0.0;
   }

   double lot_size = risk_amount / (risk_pips * tick_value);

   // Normalize the lot size according to the symbol's rules
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   lot_size = NormalizeDouble(MathFloor(lot_size / lot_step) * lot_step, 2);
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));

   DebugPrint("Position sizing for " + symbol + ": Balance=" + DoubleToString(balance, 2) + ", Risk=" + DoubleToString(risk_amount, 2) + ", RiskPips=" + DoubleToString(risk_pips, 1) + ", TickValue=" + DoubleToString(tick_value, 4) + ", CalculatedLot=" + DoubleToString(lot_size, 2));

   return lot_size;
}

//+------------------------------------------------------------------+
//| Remove a signal from the pending array after it's been actioned  |
//+------------------------------------------------------------------+
void RemovePendingSignal(int index)
{
   if(index < 0 || index >= g_pending_count) return;
   DebugPrint("Removing pending signal at index " + (string)index + " for " + g_pending_signals[index].symbol);

   // Shift remaining signals down
   for(int i = index; i < g_pending_count - 1; i++)
   {
      g_pending_signals[i] = g_pending_signals[i + 1];
   }
   g_pending_count--;
   ArrayResize(g_pending_signals, g_pending_count);
}

//+------------------------------------------------------------------+
//| Parses the signal file and populates the pending signals array   |
//+------------------------------------------------------------------+
void ProcessSignals()
{
   // Clear any old pending signals before processing the new file
   ArrayResize(g_pending_signals, 0);
   g_pending_count = 0;

   // Open and read the entire file into a string
   int fileHandle = FileOpen(InpSignalFileName, FILE_READ | FILE_TXT | FILE_COMMON);
   if(fileHandle == INVALID_HANDLE)
   {
      Print(InpEaComment, ": CRITICAL ERROR: Cannot open signal file '", InpSignalFileName, "'. Error: ", (string)GetLastError());
      return;
   }
   string fileContent = FileReadString(fileHandle);
   FileClose(fileHandle);

   if(InpLogFileContents)
      DebugPrint("File content:\n" + fileContent);

   // --- CSV PARSING LOGIC ---
   // This logic pairs "ScenarioOne" and "Alternative" rows from the CSV for the same symbol.
   struct TempSignal
   {
      string symbol;
      string s1_action; double s1_entry; double s1_target;
      string alt_action; double alt_entry; double alt_target;
      TempSignal() { symbol = ""; s1_action = ""; alt_action = ""; }
   };
   TempSignal temp_signals[];
   int temp_count = 0;

   string lines[];
   int lineCount = StringSplit(fileContent, '\n', lines);
   DebugPrint("Total lines read: " + (string)lineCount);

   for(int idx = 0; idx < lineCount; idx++)
   {
      string line = lines[idx];
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringLen(line) < 5 || StringFind(line, "Instrument") == 0) continue; // Skip empty lines/headers

      string parts[];
      if(StringSplit(line, ',', parts) < 5) continue; // Skip malformed lines

      string instrument = parts[0], scenario = parts[1], action = parts[2];
      double entry = StringToDouble(parts[3]), target = StringToDouble(parts[4]);

      if(instrument == "" || scenario == "" || action == "" || entry == 0 || target == 0) continue; // Skip invalid data

      // Find or create a temporary storage object for this symbol
      int sig_idx = -1;
      for(int t = 0; t < temp_count; t++) { if(temp_signals[t].symbol == instrument) { sig_idx = t; break; } }
      if(sig_idx == -1)
      {
         sig_idx = temp_count++;
         ArrayResize(temp_signals, temp_count);
         temp_signals[sig_idx].symbol = instrument;
      }

      // Populate the correct scenario fields
      if(scenario == "ScenarioOne")
      {
         temp_signals[sig_idx].s1_action = action;
         temp_signals[sig_idx].s1_entry = entry;
         temp_signals[sig_idx].s1_target = target;
      }
      else if(scenario == "Alternative")
      {
         temp_signals[sig_idx].alt_action = action;
         temp_signals[sig_idx].alt_entry = entry;
         temp_signals[sig_idx].alt_target = target;
      }
   }

   // --- CREATE FINAL PENDING SIGNALS ---
   // Convert the temporary paired signals into the final PendingSignal objects
   for(int t = 0; t < temp_count; t++)
   {
      // A valid signal requires both a primary and an alternative scenario to be present
      if(temp_signals[t].s1_action != "" && temp_signals[t].alt_action != "")
      {
         int new_idx = g_pending_count++;
         ArrayResize(g_pending_signals, g_pending_count);

         g_pending_signals[new_idx].symbol = temp_signals[t].symbol;
         g_pending_signals[new_idx].current_action = temp_signals[t].s1_action;
         g_pending_signals[new_idx].current_entry = temp_signals[t].s1_entry;
         g_pending_signals[new_idx].current_target = temp_signals[t].s1_target;
         // The stop loss for the primary scenario is the entry price of the alternative scenario. This is the core of the reversal logic.
         g_pending_signals[new_idx].current_stop_loss = temp_signals[t].alt_entry;
         g_pending_signals[new_idx].alt_action = temp_signals[t].alt_action;
         g_pending_signals[new_idx].alt_entry = temp_signals[t].alt_entry;
         g_pending_signals[new_idx].alt_target = temp_signals[t].alt_target;
         g_pending_signals[new_idx].signal_time = TimeCurrent();
         g_pending_signals[new_idx].scenario_one_active = true;
         g_pending_signals[new_idx].scenario_switch_price = temp_signals[t].alt_entry;

         Print(InpEaComment, ": *** PENDING SIGNAL CREATED for ", g_pending_signals[new_idx].symbol, " ***");
         Print("Primary: ", g_pending_signals[new_idx].current_action, " @ ", DoubleToString(g_pending_signals[new_idx].current_entry, _Digits), " | TP: ", DoubleToString(g_pending_signals[new_idx].current_target, _Digits), " | SL (Switch Price): ", DoubleToString(g_pending_signals[new_idx].scenario_switch_price, _Digits));
         Print("Alternative: ", g_pending_signals[new_idx].alt_action, " @ ", DoubleToString(g_pending_signals[new_idx].alt_entry, _Digits));
      }
   }
   Print(InpEaComment, ": === SIGNAL PROCESSING COMPLETE: ", (string)g_pending_count, " valid signals are now pending execution. ===");
}
//+------------------------------------------------------------------+
