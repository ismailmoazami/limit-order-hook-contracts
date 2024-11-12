// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Foundry libraries
import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

// Our contracts
import {LimitOrderHook} from "src/LimitOrderHook.sol";

contract LimitOrderHookTest is Test, Deployers {

    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency; 

    LimitOrderHook hook;

    Currency token0;
    Currency token1;

    function setUp() public {

        deployFreshManagerAndRouters();

        (token0, token1) = deployMintAndApprove2Currencies();

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        address hook_address = address(flags);

        deployCodeTo("LimitOrderHook.sol", abi.encode(manager, ""), hook_address);
        hook = LimitOrderHook(hook_address);

        MockERC20(Currency.unwrap(token0)).approve(address(hook), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(hook), type(uint256).max);

        (key, ) = initPool(token0, token1, hook, 3000, SQRT_PRICE_1_1);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function test_can_place_order() external {

        int24 tickToSell = 100; 
        bool zeroForOne = true;
        uint256 amount = 10e18;

        uint256 balanceBeforeOrder = token0.balanceOfSelf();

        int24 tickForOrder = hook.placeOrder(key, tickToSell, zeroForOne, amount);
        uint256 balanceAfterOrder = token0.balanceOfSelf();

        assertEq(tickForOrder, 60);
        assertEq(balanceBeforeOrder - balanceAfterOrder, amount);

        uint256 positionId = hook.getPositionId(key, tickForOrder, zeroForOne);
        uint256 claimTokenBalance = hook.balanceOf(address(this), positionId);

        assertEq(claimTokenBalance, amount);
    }

    function test_cancel_order() external {
        
        int24 tickToSell = 100; 
        bool zeroForOne = true;
        uint256 amount = 10e18;

        uint256 balanceBeforeOrder = token0.balanceOfSelf();

        int24 tickForOrder = hook.placeOrder(key, tickToSell, zeroForOne, amount);
        uint256 balanceAfterOrder = token0.balanceOfSelf();

        assertEq(tickForOrder, 60);
        assertEq(balanceBeforeOrder - balanceAfterOrder, amount);

        uint256 positionId = hook.getPositionId(key, tickForOrder, zeroForOne);
        uint256 claimTokenBalance = hook.balanceOf(address(this), positionId);

        assertEq(claimTokenBalance, amount);

        // cancel the order
        hook.cancelOrder(key, tickForOrder, zeroForOne, amount);
        uint256 balanceAfterCancelation = token0.balanceOfSelf();

        assertEq(balanceAfterCancelation, balanceBeforeOrder);
        
        claimTokenBalance = hook.balanceOf(address(this), positionId);
        assertEq(claimTokenBalance, 0);

    }

}