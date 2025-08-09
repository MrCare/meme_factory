// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IUniswapV2.sol";

contract TWAPOracle {
    using FixedPoint for *;

    struct Observation {
        uint32 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    mapping(address => Observation) public pairObservations;
    mapping(address => bool) public observationInitialized;
    
    IUniswapV2Factory public immutable factory;
    address public immutable WETH;
    
    uint32 public constant PERIOD = 300; // 5 minutes TWAP period
    
    event ObservationUpdated(address indexed pair, uint32 timestamp, uint256 price0Cumulative, uint256 price1Cumulative);
    
    constructor(address _factory, address _weth) {
        factory = IUniswapV2Factory(_factory);
        WETH = _weth;
    }
    
    function update(address token) external {
        address pair = factory.getPair(token, WETH);
        require(pair != address(0), "Pair does not exist");
        
        IUniswapV2Pair pairContract = IUniswapV2Pair(pair);
        uint256 price0Cumulative = pairContract.price0CumulativeLast();
        uint256 price1Cumulative = pairContract.price1CumulativeLast();
        uint32 timestamp = uint32(block.timestamp % 2**32);
        
        // Initialize observation if first time
        if (!observationInitialized[pair]) {
            pairObservations[pair] = Observation({
                timestamp: timestamp,
                price0Cumulative: price0Cumulative,
                price1Cumulative: price1Cumulative
            });
            observationInitialized[pair] = true;
        } else {
            // Update observation
            Observation storage observation = pairObservations[pair];
            uint32 timeElapsed = timestamp - observation.timestamp;
            
            // Only update if enough time has passed
            if (timeElapsed >= PERIOD) {
                observation.timestamp = timestamp;
                observation.price0Cumulative = price0Cumulative;
                observation.price1Cumulative = price1Cumulative;
                
                emit ObservationUpdated(pair, timestamp, price0Cumulative, price1Cumulative);
            }
        }
    }
    
    function getTWAPPrice(address token, uint256 amountIn) external view returns (uint256 amountOut) {
        address pair = factory.getPair(token, WETH);
        require(pair != address(0), "Pair does not exist");
        require(observationInitialized[pair], "Observation not initialized");
        
        IUniswapV2Pair pairContract = IUniswapV2Pair(pair);
        Observation memory observation = pairObservations[pair];
        
        uint256 price0Cumulative = pairContract.price0CumulativeLast();
        uint256 price1Cumulative = pairContract.price1CumulativeLast();
        uint32 timestamp = uint32(block.timestamp % 2**32);
        
        uint32 timeElapsed = timestamp - observation.timestamp;
        require(timeElapsed >= PERIOD, "Period not elapsed");
        
        // Calculate TWAP price
        bool isToken0 = pairContract.token0() == token;
        
        if (isToken0) {
            // token -> WETH
            uint256 priceAverage = (price1Cumulative - observation.price1Cumulative) / timeElapsed;
            return FixedPoint.uq112x112(uint224(priceAverage)).mul(amountIn).decode144();
        } else {
            // WETH -> token
            uint256 priceAverage = (price0Cumulative - observation.price0Cumulative) / timeElapsed;
            return FixedPoint.uq112x112(uint224(priceAverage)).mul(amountIn).decode144();
        }
    }
    
    function canUpdateTWAP(address token) external view returns (bool) {
        address pair = factory.getPair(token, WETH);
        if (pair == address(0)) return false;
        if (!observationInitialized[pair]) return true;
        
        Observation memory observation = pairObservations[pair];
        uint32 timestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = timestamp - observation.timestamp;
        
        return timeElapsed >= PERIOD;
    }
    
    function getInstantPrice(address token, uint256 amountIn) external view returns (uint256 amountOut) {
        address pair = factory.getPair(token, WETH);
        require(pair != address(0), "Pair does not exist");
        
        IUniswapV2Pair pairContract = IUniswapV2Pair(pair);
        (uint112 reserve0, uint112 reserve1,) = pairContract.getReserves();
        
        bool isToken0 = pairContract.token0() == token;
        
        if (isToken0) {
            // token -> WETH
            return (amountIn * reserve1) / reserve0;
        } else {
            // WETH -> token  
            return (amountIn * reserve0) / reserve1;
        }
    }
}
