# Limit Order Hook Contracts

This repository implements a Limit Order Hook for Uniswap v4, enabling users to place, cancel, and execute limit orders directly within Uniswap pools. The hook leverages Uniswap v4's hook system to facilitate order placement, cancellation, and execution based on specified price ticks.

## Features

- **Order Placement**: Users can place limit orders by specifying the desired price tick and amount.
- **Order Cancellation**: Users can cancel their pending orders before execution.
- **Order Execution**: Orders are executed when market conditions meet the specified price tick.
- **Token Redemption**: After order execution, users can redeem their tokens.

## Getting Started

1. **Clone the Repository**:

    ```bash
   git clone https://github.com/ismailmoazami/limit-order-hook-contracts.git
2. **Install Dependencies**:
   
    ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
3. **Install Project Dependencies**:
Navigate to the project directory and install the necessary dependencies:
    
    ```bash
    cd limit-order-hook-contracts
    forge install
4. **Compile Contracts**:
Compile the contracts using Forge:
    ```bash
    forge build
5. **Run Tests**:
Execute the test suite to ensure everything is functioning correctly:
    ```bash 
    forge test
## Usage
Placing an Order:

Call the placeOrder function with the appropriate parameters to place a limit order.

Cancelling an Order:

Use the cancelOrder function to cancel a pending order before execution.

Redeeming Tokens:

After order execution, call the redeem function to claim your tokens.

## License
This project is licensed under the MIT License. 
