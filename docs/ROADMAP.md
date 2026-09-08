# Proposed templates

These are recommendations, not contracts added by this patch. Start with assets and payments before adding lending, leverage, bridges, or stablecoins.

| Priority | Template | User benefit | Keep the first version small |
| --- | --- | --- | --- |
| 1 | Fixed-supply ERC20 | Create a community or utility token with a predictable supply | Mint once to a chosen recipient; no owner mint function, tax, or upgradeability; permit and holder burning are reasonable options |
| 2 | Payment splitter | Share revenue among collaborators | Immutable recipients and shares; pull-based native/ERC20 claims; exact rounding and total-released accounting |
| 3 | ERC1155 collection | Issue editions, tickets, memberships, or game items | OpenZeppelin ERC1155 plus supply tracking; explicit mint authority and metadata freeze; no custom marketplace |
| 4 | Deadline escrow | Hold payment until delivery or an agreed deadline | Explicit buyer/seller, mutual release, refund deadline and documented dispute rules; no arbitrary owner seizure |
| 5 | Merkle airdrop factory | Deploy the existing list-based distributor through the same factory interface | One immutable root per round, a fixed claim deadline, and recovery only after expiry in a distinct new template |
| 6 | Timelock deployment helper | Make administrative changes visible before they take effect | Compose OpenZeppelin TimelockController with a suitable owner/multisig; explain proposers, executors, cancellation and delay |
| 7 | Capped ERC20 | Allow planned issuance without unlimited owner minting | An immutable supply cap, clearly disclosed issuer role, and optional permanent mint shutdown |

Suggested order: fixed-supply ERC20, payment splitter, then ERC1155. They fit common needs and have fewer moving parts than financial protocols. Escrow needs product-level dispute design before implementation. A Merkle factory can reuse the eligibility tooling already present, but a deadline-based version should have a separate ABI and documented policy.

Avoid a generic “yield vault” that implies income without a specified strategy. ERC4626 standardizes vault shares; it does not make the underlying strategy safe. Treat lending, bridges, stablecoins, prediction markets, and leveraged strategies as separate reviewed projects.

Primary module references checked on 2026-09-08:

- [OpenZeppelin ERC20 and extensions](https://docs.openzeppelin.com/contracts/5.x/api/token/erc20)
- [OpenZeppelin ERC1155 and extensions](https://docs.openzeppelin.com/contracts/5.x/api/token/erc1155)
- [OpenZeppelin governance and TimelockController](https://docs.openzeppelin.com/contracts/5.x/api/governance)
- [OpenZeppelin Merkle tree tooling](https://github.com/OpenZeppelin/merkle-tree)

Payment splitting and escrow still require their own implementation, threat model, and tests; these are not claims that current OpenZeppelin provides a drop-in implementation for every row.
