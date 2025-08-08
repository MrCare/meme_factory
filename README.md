<!--
 * @Author: Mr.Car
 * @Date: 2025-07-30 20:59:26
-->
## clifWallet 编写

编写一个 Vesting 合约（可参考 OpenZepplin Vesting 相关合约）， 相关的参数有：

- beneficiary： 受益人
- 锁定的 ERC20 地址
- Cliff：12 个月
- 线性释放：接下来的 24 个月，从 第 13 个月起开始每月解锁 1/24 的ERC20
- Vesting 合约包含的方法 release() 用来释放当前解锁的 ERC20 给受益人，Vesting 合约部署后，开始计算 Cliff ，并转入 100 万 ERC20 资产。


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