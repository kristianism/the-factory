# Security review and patch record

Historical security-patch review. A subsequent owner-authorized cleanup changes the project license to MIT and removes the former trademark-policy file. The findings and test results below describe the reviewed patch.

Reviewed on 2026-09-08 against repository commit `8263adf5b5087489fb429e9c57b936c3e9b6c0bd`.

Scope: all first-party Solidity sources, factories, deployment scripts, tests, dependencies, and project documentation in that snapshot. Source files were retrieved through the authorized GitHub connection and checked against their Git blob hashes. This was a manual code review with local Foundry regression and fuzz testing. Codex Security was listed as installed but exposed no callable scanner in the session; no Codex Security scan, independent audit, formal verification, or live-chain validation is claimed.

## Findings and changes

Severity describes the failure under its stated conditions, not an assertion that a live deployment was exploited.

| ID | Severity | Original condition and consequence | Patch and test evidence |
| --- | --- | --- | --- |
| F-01 | High, configuration-dependent | Farm allowed the reward token as a staking token. Reward payouts could spend users' principal from the shared balance. | Reject the reward asset as an LP; `test_rewardTokenCannotBeStakedAsPrincipal`. |
| F-02 | High, token-dependent | Farm recorded requested deposits even when a transfer-taxed token delivered less, creating liabilities greater than assets. | Require exact incoming balance change and track credited principal; reject incompatible transfers atomically. `test_rejectsTaxedDepositsWithoutCreatingLiabilities` and deposit-fee fuzz test. |
| F-03 | Medium | Underfunded rewards were truncated to the available balance, but reward debt advanced by the full entitlement, erasing the shortfall. | Persist unpaid rewards, including after full withdrawal, and use SafeERC20; `test_shortfallSurvivesFullWithdrawalAndLaterFunding`. |
| F-04 | Medium | Reward denominator used raw token balance. Direct donations diluted earned rewards. | Use recorded `totalStaked` per pool; `test_donationsDoNotDiluteRewards`. |
| F-05 | Medium | An allocation change with `_withUpdate=false` applied new weights retroactively. | Always checkpoint pools before changing weights; cap pool count at 50 and allocation points at uint64. `test_allocationChangeCheckpointsOldRewardsEvenWithFalseFlag`. |
| F-06 | Low, view availability | `pendingReward` divided by zero when all weights were zero and a pool held stake. | Explicit zero-allocation handling; `test_zeroAllocationDoesNotDivideByZero`. |
| F-07 | Medium, token-dependent | Farm reward payments called ERC20 `transfer` directly and required a boolean, reverting for successful tokens returning no data. | SafeERC20 payout; `test_noReturnRewardTokenCanPay`. |
| F-08 | Medium | Yield-farm factory accepted creation fees but exposed no authorized withdrawal wrapper, stranding fees. | Add collection, token recovery, and collector setter wrappers; `test_yieldFactoryFeesCanBeCollected`. |
| F-09 | Medium, deployment error | Factories accepted code-less implementation addresses. A clone could appear created while initialization performed no logic. | Reject implementations without code in all six factories; `test_allFactoriesRejectImplementationWithoutCode`. Code presence is not an implementation audit. |
| F-10 | Low | NFT required-field checks compared unsigned lengths with `< 0`, so empty fields passed. Every factory's validity lookup also accepted address zero through default mapping values. | Correct comparisons and reject zero in registry lookups; `test_nftRejectsEmptyFields` and `test_allRegistriesRejectZeroAddress`. |
| F-11 | Low, fee economics | Vesting used OR instead of AND in referral eligibility, permitting direct self-referrals. | Correct eligibility and enforce it again in Referral; `test_vestingCannotPaySelfReferral`. Separate wallets can still obtain referrals. |
| F-12 | Low, extreme values | Tax arithmetic multiplied before checking exemptions, so sufficiently large mints or transfers reverted even when no tax applied. | Check exemptions first and use full-precision `Math.mulDiv`, preserving upward rounding; `test_taxMintAndTransferSupportFullUintSupply`. |

Further hardening and explicit behavior changes:

- Farm emergency withdrawal checkpoints rewards before removing stake, avoiding redistribution of past rewards to remaining stakers. Emergency withdrawal forfeits the exiting account's unpaid rewards.
- Farm update entry points and factory fee/administration paths share reentrancy protection. A callback staking-token test confirms that pool updates are rejected during deposit. Treasury collection/recovery also uses a guard.
- Registration airdrop reserves funded allocations. Public and batch registration cannot exceed available funds; withdrawals are limited to unallocated surplus. This changes the old administrative policy, which allowed underfunded promises and unrestricted owner withdrawal. Tests cover atomic batch failure, reserved balances, repeat claims, and invalid recipients/amounts.
- Registration pagination avoids `offset + limit` overflow. `canClaim` includes a balance check.
- Vesting release can be triggered by anyone but always pays its beneficiary. Renouncing ownership is disabled to avoid permanently stranded assets. Wallet ownership transfers remain possible.
- Referral sends have a 100,000-gas budget; a failed send stays in the factory under the existing fallback policy. Exact-payment callers need no refund receiver.
- Most administrative ownership now requires acceptance by the proposed owner. Vesting retains its underlying wallet's ownership transfer. StandardERC20 adds ERC-2612 permit; tests cover replay, cross-clone signing domains, and locked initialization.
- The FeeCollector test now uses an atomically initialized ERC1967Proxy and verifies access control, failed-factory isolation, locked initialization, and a fresh-proxy upgrade.

## Verification

Original baseline: **42 tests passed** using the original source, lockfile, and Solidity 0.8.28. The old treasury test contained no test functions, and the yield and airdrop paths were untested.

Seven assertions were then run against an isolated copy of the original farm, retaining its original dependency lockfile and compiler. Only the test pragma and the unavailable new custom-error selector were adapted to compile against the original ABI. All seven failed as expected:

| Regression | Original result | Patched result |
| --- | --- | --- |
| Historical allocation checkpoint | 10 tokens instead of 15 | Pass |
| Donation-independent rewards | 1 token instead of 10 | Pass |
| No-return reward token | Reverted | Pass |
| Reject taxed deposit | Accepted incompatible deposit | Pass |
| Separate reward/staking assets | Accepted same asset | Pass |
| Preserve funding shortfall | 0 tokens owed instead of 7 | Pass |
| Zero allocation view | Division-by-zero panic | Pass |

Patched validation:

- `FOUNDRY_PROFILE=ci forge test`: **71 passed, 0 failed, 0 skipped**, eight suites.
- The deposit-fee fuzz test ran **1,000 cases**, comparing recorded user stake, total stake, and actual token balance through deposit and withdrawal.
- `forge build --sizes`: passed. Largest first-party production runtime: **StandardYieldFarm, 7,798 bytes**, below the 24,576-byte EVM contract limit.
- `forge fmt --check` and `git diff --check`: passed.
- At the time of the security patch, branding searches excluded the then-existing legal notices. The subsequent owner-authorized cleanup adopts MIT and removes the former trademark-policy file. Historical network names/addresses remain explicitly labeled as unverified deployment history.
- Compiler/linter notices about intentional timestamp-based vesting/rewards and test-token return handling are not proof of a vulnerability. Compiler warning 6335 is suppressed for forward-compatibility identifier notices in pinned dependencies.

Toolchain: Foundry 1.7.1, Solidity 0.8.36, Cancun EVM target, optimizer 200 runs, OpenZeppelin 5.6.1, forge-std 1.16.2 (`bf647bd6046f2f7da30d0c2bf435e5c76a780c1b`). CI installs the locked npm dependencies and runs on pushes and pull requests.

## Remaining trust boundaries and release work

1. No claim is made that all possible vulnerabilities have been eliminated. External assets, compromised administrators, economic attacks, integration behavior, and future dependency issues remain relevant. No Slither scan or formal verification was performed.
2. Farms do not generate or guarantee yield. Accrual can exceed funding; it is now recorded as debt. Transfer-taxed/rebasing assets, malicious tokens, tokens that change behavior, or token blacklisting are unsupported. A faulty reward asset can block normal claims; emergency exit bypasses reward transfers but still depends on the staking token.
3. Owners retain the disclosed minting, metadata, tax, allocation, deposit-fee, airdrop, and treasury-upgrade powers. A 100% deposit fee is possible and must be shown by any frontend. Merkle owners can still change the root or withdraw tokens; this review did not silently replace that policy. Open registration is vulnerable to multiple-wallet participation by design.
4. Existing clones are immutable and need replacement deployments. New FeeCollector behavior has only been tested on freshly initialized proxies. No storage-layout approval or migration simulation for an existing proxy was performed.
5. No contracts were deployed, no transactions were sent on-chain, and historical addresses were not checked against live bytecode. Check the actual target network's Cancun support and verify deployed source separately.
6. Resolved by subsequent owner instruction: the project now uses the MIT license. Third-party dependencies keep their respective licenses and notices.
7. The GitHub repository's About description still contains the old branding. The connected tools do not expose repository-metadata editing. Suggested replacement: **Readable smart contract factories for tokens, NFTs, vesting, airdrops, and staking.**

## Primary references

- [OpenZeppelin 5.x changelog](https://docs.openzeppelin.com/contracts/5.x/changelog): current module locations, stateless ReentrancyGuard/Initializable/UUPS changes, and 5.6.1 release.
- [Solidity 0.8.36 release](https://www.soliditylang.org/blog/2026/07/09/solidity-0.8.36-release-announcement/): selected stable compiler release.
- [OpenZeppelin ERC20 modules](https://docs.openzeppelin.com/contracts/5.x/api/token/erc20): permit, SafeERC20, and token extensions.
