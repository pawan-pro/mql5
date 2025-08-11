# Signal Processor EA - Professional Edition

The Signal Processor EA is a professional-grade trade execution utility for MetaTrader 5. It is not a signal generator; instead, it acts as a sophisticated "trade copier" that reads instructions from an external CSV file. This allows traders to separate their signal generation (whether manual, from another system, or from a third-party service) from their trade execution.

This EA is built for reliability and flexibility, featuring advanced logic for scenario-switching and robust risk management.

## Core Logic & Strategy

The EA's primary function is to monitor a specified CSV file for new trade signals. When the file is updated, the EA parses its contents and sets up "pending signals" to be monitored.

The key feature is its ability to handle **two scenarios** for each instrument:

1.  **Primary Scenario:** The main trade idea (e.g., "Buy EURUSD at 1.0850").
2.  **Alternative Scenario:** A contingency plan if the market moves against the primary idea (e.g., "If price drops to 1.0820 instead, sell EURUSD").

The EA will monitor the primary signal. If the market hits the entry for the primary signal, it will execute the trade. However, if the market moves against the primary signal and hits the entry price of the alternative signal, the EA will automatically cancel the primary idea and activate the alternative one. This provides a powerful, automated way to react to changing market conditions.

## Features

-   **External Signal Processing:** Reads trade signals from a user-defined CSV file.
-   **Dual-Scenario Logic:** Handles both a primary and an alternative trade idea for each symbol.
-   **Automatic Scenario Switching:** If the market invalidates the primary signal by hitting the alternative entry, the EA automatically pivots to the alternative strategy.
-   **Advanced Risk Management:** Automatically calculates lot size based on a fixed percentage of the account balance.
-   **Pre-Trade Safety Checks:** Performs comprehensive checks on trading permissions, symbol status, and market conditions before placing any trade.
-   **Robust Error Handling:** Provides clear, detailed feedback on all operations, especially trade failures.
-   **Highly Configurable:** A wide range of inputs allows you to tailor the EA's behavior to your exact needs.

## How to Format the `signals.csv` File

The EA reads a CSV file with a specific format. The file must contain the following columns: `Instrument,Scenario,Action,Entry,Target`.

-   `Instrument`: The market symbol (e.g., `EURUSD`).
-   `Scenario`: Must be either `ScenarioOne` for the primary idea or `Alternative` for the contingency plan.
-   `Action`: The trade direction, either `Buy` or `Sell`.
-   `Entry`: The target entry price for the signal.
-   `Target`: The take profit price for the signal.

**Crucially, for every `ScenarioOne`, there must be a corresponding `Alternative` row for the same instrument.** The EA uses the entry of the `Alternative` scenario as the stop loss for `ScenarioOne`.

### Example `signals.csv` content:

```csv
Instrument,Scenario,Action,Entry,Target
EURUSD,ScenarioOne,Buy,1.08500,1.09500
EURUSD,Alternative,Sell,1.08200,1.07700
GBPUSD,ScenarioOne,Sell,1.27000,1.26000
GBPUSD,Alternative,Buy,1.27300,1.27800
```

In this example:
-   For EURUSD, the EA will look to **Buy at 1.08500**. The Stop Loss will be automatically set to **1.08200** (the alternative entry). If the price drops to 1.08200 before the buy is triggered, the EA will switch and instead look to **Sell at 1.08200**.
-   For GBPUSD, the EA will look to **Sell at 1.27000** with a Stop Loss at **1.27300**.

## Input Parameters

### --- Core Settings ---
-   `InpMagicNumber` (Default: 67890): A unique number to identify trades managed by this EA instance.
-   `InpEaComment` (Default: "SignalProcessor"): A custom comment for all trades.
-   `InpSignalFileName` (Default: "signals.csv"): The name of your signal file. This file must be placed in the `MQL5/Files` folder or the `Terminal/Common/Files` folder.
-   `InpTimerFrequency` (Default: 5): How many seconds between each check of the signal file for updates.

### --- Risk Management ---
-   `InpFixedPercentageRisk` (Default: 1.0): The percentage of your account balance to risk on a single trade. The EA uses this to calculate the lot size.
-   `InpMinimumAcceptableRRR` (Default: 1.5): The minimum Risk-to-Reward ratio required to open a trade. Trades with a lower ratio will be ignored.

### --- Entry Logic ---
-   `InpWaitForEntryPrice` (Default: true): If true, the EA waits for the market to reach the signal's entry price. If false, it executes the trade immediately at the current market price as soon as a new signal is processed.
-   `InpEnableScenarioSwitch` (Default: true): Enables the automatic switching from the primary to the alternative scenario.
-   `InpEntryTolerance...`: These inputs define a dynamic tolerance zone around the entry price (based on ATR) to account for volatility and increase the chance of a fill.

### --- Execution & Safety ---
-   `InpSpreadMultiplierForStop` (Default: 2.0): A safety feature that prevents setting a stop loss too close to the entry price, relative to the current spread.
-   `InpSlippage` (Default: 10): The maximum allowed slippage in points for trade execution.

### --- Debug & Logging ---
-   `InpEnableDebugMode` (Default: true): Enables verbose logging in the "Experts" tab, useful for seeing the EA's operations in detail.
-   `InpLogFileContents` (Default: false): If true, the EA will print the entire content of the CSV file to the log. Use this only for debugging parsing issues, as it can be very verbose.
-   `InpEnableTradingStatusCheck` (Default: true): Enables periodic checks of your terminal's trading permissions.

## How to Use

1.  Place the `SignalProcessorEA.mq5` file in your `MQL5/Experts/` folder and compile.
2.  Create your `signals.csv` file using the format described above.
3.  Place your `signals.csv` file in the `MQL5/Files` folder (accessible via `File > Open Data Folder` in MT5).
4.  Drag the "SignalProcessorEA" onto any chart. The chart it's on does not matter, as it trades the symbols specified in your CSV.
5.  Configure the inputs, ensuring `InpSignalFileName` matches your file's name.
6.  Enable the "Algo Trading" button in the MT5 toolbar.
7.  Click "OK". The EA will now wait for your `signals.csv` file to be created or updated.
