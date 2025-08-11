# Oscillator EA - Free Version

A robust and reliable Expert Advisor for MetaTrader 5 that implements a classic trading strategy based on three popular indicators: RSI, Stochastic, and MACD. This EA is designed to be easy to use and understand, making it a perfect starting point for traders new to automation.

## Strategy

The EA's logic is based on the principle of "confluence," meaning it waits for multiple indicators to agree before entering a trade. It opens only one trade at a time.

-   **Buy Signal:** A buy trade is opened when:
    1.  The **RSI** is in the oversold area (below the `InpRsiTriggerBuy` level).
    2.  The **Stochastic** is also in the oversold area (below the `InpStochTriggerBuy` level).
    3.  (Optional) The **MACD** indicates an uptrend (Main line is above the Signal line on a higher timeframe).

-   **Sell Signal:** A sell trade is opened when:
    1.  The **RSI** is in the overbought area (above the `InpRsiTriggerSell` level).
    2.  The **Stochastic** is also in the overbought area (above the `InpStochTriggerSell` level).
    3.  (Optional) The **MACD** indicates a downtrend (Main line is below the Signal line on a higher timeframe).

## Features

-   **Easy to Use:** Simply attach to a chart and configure the inputs.
-   **Clear Signals:** The EA only trades when all selected indicators align.
-   **Built-in Risk Management:** Automatically calculates Take Profit and Stop Loss based on a percentage of the entry price.
-   **Trailing Stop:** Protects profits by trailing the Stop Loss as the price moves in your favor.
-   **Professional Code:** Fully refactored to professional standards with robust error handling and clear status messages.

## Input Parameters

### --- Magic Number & Comment ---
-   `InpMagicNumber` (Default: 12345): A unique number that the EA uses to identify its own trades. Make sure this is different for every EA running on your account.
-   `InpEaComment` (Default: "OscillatorEA"): A custom comment to apply to all trades opened by this EA.

### --- Lot Sizing ---
-   `InpLots` (Default: 0.01): The fixed lot size for every trade.

### --- Position Management ---
-   `InpTpPercent` (Default: 1.0): The Take Profit distance as a percentage of the entry price. For example, a value of 1.0 on a 1.20000 entry would place the TP at 1.21200.
-   `InpSlPercent` (Default: 0.5): The Stop Loss distance as a percentage of the entry price.
-   `InpTslPercent` (Default: 0.5): The distance the Trailing Stop will maintain from the current price, as a percentage.
-   `InpTslTriggerPercent` (Default: 0.2): The percentage the price must move in your favor before the trailing stop is activated.

### --- Indicator Timeframes ---
-   `InpSignalTimeframe` (Default: H1): The timeframe on which the RSI and Stochastic indicators are calculated.
-   `InpFilterTimeframe` (Default: H4): The timeframe for the MACD trend filter. This should typically be higher than the signal timeframe.

### --- Entry Signal Settings ---
-   `InpRsiTriggerSell` (Default: 70.0): The RSI level above which a sell signal is considered.
-   `InpRsiTriggerBuy` (Default: 30.0): The RSI level below which a buy signal is considered.
-   `InpStochTriggerSell` (Default: 80.0): The Stochastic level above which a sell signal is considered.
-   `InpStochTriggerBuy` (Default: 20.0): The Stochastic level below which a buy signal is considered.
-   `InpMacdFilterMode` (Default: FILTER_TREND): How to use the MACD.
    -   `FILTER_DISABLED`: The MACD indicator is ignored.
    -   `FILTER_TREND`: Only allow trades that go in the same direction as the trend defined by the MACD on the higher timeframe.

### --- RSI, Stochastic, MACD Settings ---
-   These groups contain the standard parameters for each indicator (Periods, Applied Price, etc.) that you can customize to fit your strategy.

## How to Use

1.  Open the MetaEditor in MT5.
2.  Copy the `OscillatorEA.mq5` file into your `MQL5/Experts/` folder.
3.  Compile the file in MetaEditor (or restart MT5).
4.  Find "OscillatorEA" in the Navigator window under "Expert Advisors".
5.  Drag the EA onto the chart you wish to trade.
6.  Adjust the input parameters as needed in the "Inputs" tab.
7.  Ensure the "Algo Trading" button in the MT5 toolbar is enabled.
8.  Click "OK". The EA will now monitor the market for trading opportunities.
