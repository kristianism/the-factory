# The Factory

A smart contract toolkit maintained by [Kristian](https://github.com/kristianism). Create tokens, NFT collections, vesting wallets, airdrops, and staking reward pools with small, readable templates.

**This is a contract repository, not a finished no-code application.** Factories create and initialize minimal proxy clones in one transaction. Each clone keeps its implementation permanently. The `Upgradeable` library names refer to initialization support; they do not make these clones upgradeable. The separate FeeCollector uses an owner-controlled UUPS proxy.

## Choose a template

| Template | What it does | What the owner can do |
| --- | --- | --- |
| Standard ERC20 | Transfer, burn, and approve tokens, including approvals by signature (ERC-2612) | Mint more tokens; transfer or renounce ownership |
| Tax token | Deduct a transfer tax, rounded up in smallest units | Mint; set tax up to 20%; change exemptions and beneficiary |
| Standard NFT | Mint ERC721 collectibles with a shared metadata URI | Mint without a supply cap; edit metadata until permanently locked |
| Vesting wallet | Release native assets or ERC20 tokens over time; duration zero means a timelock | Transfer beneficiary ownership; cannot renounce it |
| Registration airdrop | Reserve a funded amount for each registered address | Open registration/claims, batch-register, set future allocations, withdraw unallocated surplus |
| Merkle airdrop | Check inclusion in an off-chain eligibility list before paying | Replace the root and withdraw funds; claims are once per address for the contract's lifetime |
| Staking reward farm | Distribute externally funded tokens among stakers | Add up to 50 pools, change reward weights/emissions and deposit fees up to 100% |

Amounts are integers in the asset's **smallest unit**. For an 18-decimal token, `1 ether` in Solidity means `1_000_000_000_000_000_000` token units. It does not mean the token has an ETH price. Fees in basis points use 10,000 = 100%.

Read the [plain-language guide](docs/CONTRACT_GUIDE.md), [security review](docs/SECURITY_REVIEW.md), and [next-template roadmap](docs/ROADMAP.md).

## Development

Pinned versions: Solidity **0.8.36**, OpenZeppelin Contracts and Contracts Upgradeable **5.6.1**, forge-std **1.16.2**, and Foundry **1.7.1** for CI. The EVM target is **Cancun**; confirm the target chain supports it.

```sh
git clone --recurse-submodules https://github.com/kristianism/the-factory.git
cd the-factory
npm ci --ignore-scripts
forge fmt --check
forge build --sizes
FOUNDRY_PROFILE=ci forge test -vv
```

If you already cloned the repository, run `git submodule update --init --recursive`. Install the pinned Foundry release before running Forge. CI runs on pull requests and pushes and installs the npm dependencies before compilation.

## Deployment

Start with a local chain or testnet. Deploy an implementation, then a factory pointing to that implementation. Factories start paused. Check the implementation code, owner, fee collector, creation fee, referral rate, and target chain before the owner unpauses.

`script/DeployStandardNFT.sol` reads `OWNER`, `COLLECTOR`, `CREATION_FEE`, and `REFERRAL_RATE`. Use a keystore or hardware wallet for signing. Supply `RPC_URL` and explorer settings for your chosen network. The script deliberately leaves the factory paused so the deployment signer need not also be the long-term owner.

For FeeCollector, deploy an `ERC1967Proxy` with initialization calldata in its constructor; do not call `initialize` directly on the locked implementation. Its owner can replace the collection logic. A multisig is a suitable owner if several people share responsibility.

These patches require **new implementations and factories**. Existing clones cannot be patched in place. Existing FeeCollector proxies have not been cleared for a live upgrade; compare storage layouts and simulate migration separately. [Addresses and deployment history](ADDRESSES.md).

## Limits and permissions

- Factory owners control future creation fees and pausing; this does not pause existing clones.
- Ownership uses two-step acceptance in factories, tokens, NFTs, airdrops, farms, and FeeCollector. Vesting uses the underlying wallet's ownership transfer.
- The farm requires distinct staking and reward assets. Transfer-taxed, rebasing, or otherwise nonstandard assets are unsupported. Taxed incoming stake transfers are rejected.
- Unpaid farm rewards remain claimable after funding arrives. They are liabilities, not a guarantee of future payment. Emergency withdrawal forfeits rewards.
- Open registration is per address, not per person. It provides no Sybil protection.
- A code-bearing implementation address is necessary, but does not prove the implementation is correct. Use the reviewed template and record its code hash.
- Tests and this review do not constitute an independent audit or a guarantee against losses.

## License

The repository retains its existing [LICENSE](LICENSE) and [trademark notice](TRADEMARKS.md). Product branding has been replaced, but this change does not relicense the inherited source or remove its restrictions. Do not describe this release as permissively licensed open source. Rights and a suitable license for broader production use need to be resolved separately.
