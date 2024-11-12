// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

contract LimitOrderHook is BaseHook, ERC1155{

    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using FixedPointMathLib for uint256;

    // Events
    event OrderPlaced(address user, PoolKey key, int24 tick, bool zeroForOne, uint256 inputAmount);
    event OrderCanceled(address user, PoolKey key, int24 tick, bool zeroForOne, uint256 inputAmount);
    event TokensClaimed(address user, PoolKey key, int24 tick, bool zeroForOne, uint256 outputAmount);

    // Errors
	error InvalidOrder();
	error NothingToClaim();
	error NotEnoughToClaim();

    mapping(
        PoolId poolId => mapping(
            int24 tickToSell => mapping(
                bool zeroForOne => uint256 amount
            )
        )
    ) public pendingOrders;

    mapping(uint256 positionId => uint256 claimsSupply) public claimTokensSupply;
    mapping(uint256 positionId => uint256 outputClaimable) public claimableOutputTokens;

    constructor(IPoolManager _manager, string memory _uri) BaseHook(_manager) ERC1155(_uri) {}

    function getHookPermissions()
            public
            pure
            override
            returns (Hooks.Permissions memory)
        {
            return
                Hooks.Permissions({
                    beforeInitialize: false,
                    afterInitialize: true,
                    beforeAddLiquidity: false,
                    beforeRemoveLiquidity: false,
                    afterAddLiquidity: false,
                    afterRemoveLiquidity: false,
                    beforeSwap: false,
                    afterSwap: true,
                    beforeDonate: false,
                    afterDonate: false,
                    beforeSwapReturnDelta: false,
                    afterSwapReturnDelta: false,
                    afterAddLiquidityReturnDelta: false,
                    afterRemoveLiquidityReturnDelta: false
                });
        }

    function afterInitialize(address, PoolKey calldata, uint160, int24) 
        external 
        override 
        onlyPoolManager
        returns (bytes4)
    {
        return(this.afterInitialize.selector);        
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata) 
        external
        override
        onlyPoolManager
        returns (bytes4, int128)
    {
        return(this.afterSwap.selector, 0);
    }

    function placeOrder(PoolKey calldata _key, int24 _tickToSell, bool _zeroForOne, uint256 _inputAmount) 
    external 
    returns(int24) {
        int24 tick = getLowerUsableTick(_tickToSell, _key.tickSpacing); 
        pendingOrders[_key.toId()][tick][_zeroForOne] += _inputAmount; 

        uint256 positionId = getPositionId(_key, tick, _zeroForOne);
        claimTokensSupply[positionId] += _inputAmount;
        _mint(msg.sender, positionId, _inputAmount, "");

        address tokenToSell = _zeroForOne ? Currency.unwrap(_key.currency0) : Currency.unwrap(_key.currency1);
        IERC20(tokenToSell).transferFrom(msg.sender, address(this), _inputAmount);

        emit OrderPlaced(msg.sender, _key, tick, _zeroForOne, _inputAmount);
        return tick;    
    }

    function cancelOrder(PoolKey calldata _key, int24 _tickToSell, bool _zeroForOne, uint256 _amountToCancel)
    external 
    {
        int24 tick = getLowerUsableTick(_tickToSell, _key.tickSpacing); 
        uint256 positionId = getPositionId(_key, tick, _zeroForOne); 

        uint256 balanceOfUser = balanceOf(msg.sender, positionId);
        if(balanceOfUser < _amountToCancel){
            revert NotEnoughToClaim();
        }
        pendingOrders[_key.toId()][tick][_zeroForOne] -= _amountToCancel;
        claimTokensSupply[positionId] -= _amountToCancel;
        _burn(msg.sender, positionId, _amountToCancel);

        address token = _zeroForOne ? Currency.unwrap(_key.currency0) : Currency.unwrap(_key.currency1);
        IERC20(token).transfer(msg.sender, _amountToCancel);
        emit OrderCanceled(msg.sender, _key, tick, _zeroForOne, _amountToCancel);

    }

    function redeem(PoolKey calldata _key, int24 _tickToSell, bool _zeroForOne, uint256 _inputAmountToRedeem)
    external 
    {
        int24 tick = getLowerUsableTick(_tickToSell, _key.tickSpacing);
        uint256 positionId = getPositionId(_key, tick, _zeroForOne);

        uint256 totalOutputTokens = claimableOutputTokens[positionId];
        if(totalOutputTokens == 0) {
            revert NothingToClaim();
        }

        uint256 balanceOfUser = balanceOf(msg.sender, positionId);
        if(balanceOfUser < _inputAmountToRedeem) {
            revert NotEnoughToClaim();
        }
        uint256 totalInputTokens = claimTokensSupply[positionId];
        uint256 amountToRedeem = _inputAmountToRedeem.mulDivDown(totalOutputTokens, totalInputTokens);

        claimableOutputTokens[positionId] -= amountToRedeem;
        claimTokensSupply[positionId] -= _inputAmountToRedeem;
        _burn(msg.sender, positionId, _inputAmountToRedeem);

        Currency token = _zeroForOne ? _key.currency1 : _key.currency0;
        token.transfer(msg.sender, amountToRedeem);

        emit TokensClaimed(msg.sender, _key, tick, _zeroForOne, amountToRedeem);
    }

    function getPositionId(PoolKey calldata _key, int24 _tick, bool _zeroForOne) 
    public 
    pure 
    returns(uint256) {
        return uint256(keccak256(abi.encode(_key, _tick, _zeroForOne)));
    }


    // Internal functions
    function getLowerUsableTick(int24 _tick, int24 _tickSpacing) 
    internal 
    pure 
    returns(int24) 
    {
        int24 intervals = _tick / _tickSpacing; 
        if(_tick < 0 && _tick % _tickSpacing != 0) {
            intervals -= 1;
        }
        return intervals * _tickSpacing;
    } 

}