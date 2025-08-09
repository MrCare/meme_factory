<!--
 * @Author: Mr.Car
 * @Date: 2025-07-30 20:59:26
-->
## Meme工厂

基于EVM链的Meme代币发射平台，使用EIP-1167最小代理模式，集成Uniswap V2和TWAP价格预言机。

### 技术实现

#### 🚀 最小代理架构
- **EIP-1167标准**: 45字节代理合约delegatecall到实现合约
- **CREATE2部署**: 确定性地址生成，支持预计算代币地址
- **模板合约**: 单一Meme.sol作为所有代币的逻辑实现
- **初始化模式**: proxy部署后调用initialize()而非constructor

#### 💰 费用分配机制
- **5%平台费率**: 使用500/10000的费率常量
- **自动流动性注入**: 平台费用直接调用Uniswap V2 Router addLiquidityETH
- **CREATE2配对**: 自动创建Token/WETH交易对
- **LP代币归属**: 流动性代币分配给代币创建者

#### 🏪 双重价格源
- **工厂mint价格**: 固定价格 * perMint数量
- **Uniswap即时价格**: 通过getAmountsOut获取
- **TWAP价格**: 5分钟时间窗口的cumulative price计算
- **价格比较逻辑**: _getBestPrice()函数自动选择最优源

#### 📊 TWAP预言机实现
- **cumulative price tracking**: 记录price0CumulativeLast和price1CumulativeLast
- **FixedPoint数学库**: 处理Q112.112格式的价格累计值
- **300秒更新周期**: 防止短期价格操纵攻击
- **fallback机制**: TWAP失败时降级到即时价格

### 测试结果

#### MemeFactory 基础功能测试
```Shell
Ran 9 tests for test/MemeFactoryBasic.t.sol:MemeFactoryBasicTest
[PASS] testCalculateMintCost() (gas: 461495)
[PASS] testCannotDeployDuplicateSymbol() (gas: 464082)
[PASS] testCannotDeployInvalidParams() (gas: 33306)
[PASS] testCannotMintInsufficientPayment() (gas: 471032)
[PASS] testCannotMintNonexistentMeme() (gas: 21157)
[PASS] testDeployMeme() (gas: 474531)
[PASS] testDeployMemeEmitsEvent() (gas: 464130)
[PASS] testGetAllMemes() (gas: 884164)
[PASS] testGetMemeInfo() (gas: 471102)
Suite result: ok. 9 passed; 0 failed; 0 skipped
```

#### MemeFactory TWAP 和 Uniswap 集成测试
```Shell
Ran 5 tests for test/MemeFactoryTWAP.t.sol:MemeFactoryWithTWAPTest
[PASS] testDeployMemeWithLiquidity() (gas: 470994)
[FAIL: Pair does not exist] testBuyMemeChoosesBestPrice() (gas: 2957648)
[FAIL: Pair does not exist] testMintMemeAddsLiquidity() (gas: 2961048)
[FAIL: Pair does not exist] testMultipleBuysWithDifferentSources() (gas: 2962842)
[FAIL: Pair does not exist] testTWAPOracle() (gas: 2957606)
Suite result: FAILED. 1 passed; 4 failed; 0 skipped
```

**注**: TWAP测试需要Sepolia网络环境，已配置环境变量支持。

### 合约架构

#### 核心合约
- **MemeFactory.sol**: 工厂合约，管理部署、mint、费用分配和流动性操作
- **MinimalProxy.sol**: EIP-1167代理工厂，CREATE2部署代理实例
- **Meme.sol**: ERC20实现合约，delegatecall执行目标
- **TWAPOracle.sol**: 时间加权平均价格预言机，防MEV攻击
- **CliffWallet.sol**: 线性释放锁仓合约(独立模块)

#### 技术特点
- **Gas优化**: 45字节代理 vs 标准ERC20合约
- **安全机制**: reentrancy guard、owner权限控制、TWAP防操纵
- **模块化**: 接口分离、可升级预言机、可扩展费用模型
- **标准兼容**: ERC20、EIP-1167、Uniswap V2接口

#### 网络配置
- **Sepolia Testnet**: 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008 (Router)
- **Uniswap V2 Factory**: 0x7E0987E5b3a30e3f2828572Bb659A548460a3003
- **WETH**: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9

### API接口

```solidity
// 部署代币
function deployMeme(
    string memory symbol,      // 代币符号
    uint256 totalSupply,      // 最大供应量
    uint256 perMint,          // 每次mint数量  
    uint256 price             // 单价(wei)
) external returns (address)

// 固定价格mint
function mintMeme(address tokenAddr) external payable returns (bool)

// 最优价格购买
function buyMeme(address tokenAddr) external payable returns (bool)

// 价格查询
function getPriceInfo(address tokenAddr, uint256 ethAmount) 
    external view returns (uint256, uint256, bool, bool)
```

## CliffWallet 线性释放

OpenZeppelin VestingWallet参考实现，支持cliff period + 线性释放模式。

#### 参数配置
- **beneficiary**: 受益人地址
- **token**: 锁定的ERC20代币地址  
- **cliff**: 12个月锁定期
- **duration**: 24个月线性释放期(第13-36个月)
- **amount**: 锁定数量(1,000,000 tokens)

#### 核心函数
```solidity
function release() external                    // 释放可解锁代币
function releasable() external view returns (uint256)  // 查询可释放数量
function released() external view returns (uint256)    // 查询已释放数量
```


```Shell
Ran 11 tests for test/CliffWallet.t.sol:CliffWalletTest
[PASS] test_CliffTiming() (gas: 22180)
[PASS] test_Constructor() (gas: 27742)
[PASS] test_FullVestingCycle() (gas: 76383)
[PASS] test_LinearVesting() (gas: 40441)
[PASS] test_MultipleReleases() (gas: 81206)
[PASS] test_ReleasableAfterCliff() (gas: 19103)
[PASS] test_ReleasableBeforeCliff() (gas: 18557)
[PASS] test_Release() (gas: 83501)
[PASS] test_ReleaseAfterFullVesting() (gas: 73957)
[PASS] test_ReleaseFailsBeforeCliff() (gas: 16357)
[PASS] test_VestingMath() (gas: 35919)
Suite result: ok. 11 passed; 0 failed; 0 skipped; finished in 1.93ms (3.40ms CPU time)

Ran 1 test suite in 576.61ms (1.93ms CPU time): 11 tests passed, 0 failed, 0 skipped (11 total tests)
```