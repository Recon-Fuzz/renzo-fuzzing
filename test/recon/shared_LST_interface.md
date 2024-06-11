## A shared interface for all LST tokens supported by EigenLayer

- currently Renzo plans to support ezETH (their token which would be a liquid restaking token), stETH, wBETH

- primary logic of interest for fuzzing is how the token handles rebasing (receiving staking rewards) so that we can replicate this with the fuzzer

- because minting/burning logic is specific to each token but not relevant to what we want to test, excluding it from the interface
	- since this interface will only be used for fork testing to wrap the actually deployed LST tokens with extra functionality, instead of minting, can transfer from a whale address to the target user
	- burning is irrelevant here because no LSTs are redeemed for their underlying ETH in any logic in Renzo or EigenLayer

- rebasing LSTs only need to be simulated in the Renzo system locally via a change in the price of the LST/ezETH which user receives when depositing
	- when a user is withdrawing from the system, accounting for the amount withdrawn is via the amount of ezETH and LST tokens held by the system, so independent of price returned by oracle
	- an increase in the price of the LST relative to ezETH would indicate a rebasing event 
		- user receives more ezETH when depositing
	- because price in the Renzo system is determined by an oracle, we can just introduce a function (`restakeManager_LST_rebase`) that increases the price of the LST relate to ezETH to simulate a rebase  
		- given that stETH has a [max daily rebase limit](https://docs.lido.fi/guides/lido-tokens-integration-guide/#accounting-oracle) of .074%, this will have a proportional increase on the exchange rate returned by the oracle (NOTE: not quite sure of this, might require more proof that increase in supply is directly proportional to price, oracle calculation may disprove this)

- accounting for LSTs used in Renzo is virtual, meaning that the actual supply of the tokens doesn't change with a rebase event 
	- the result is that only the exchange rate between the LST/ezETH is effected during a rebase event and so is the only thing that needs to be simulated to replicate a rebase in the system 
		

- starting with implementing a shared interface for stETH, wBETH for simplicity because they're what's supported by Renzo:
	- [stETH](https://etherscan.io/address/0x17144556fd3424edc8fc8a4c940b2d04936d17eb#code)
		- uses `_mintShares` to create more shares and assign them to a recipient without increasing the token total supply
			- this is called in `_distributeFee` to distribute the rewards earned by the protocol for the pooled staked ETH
				- this is called in `_processRewards` to actually distribute the rewards to all token holders
					- this is called by `_handleOracleReport` which performs all rebasing updates
		- to update the number of shares and simulate a rebase therefore, need to pass in a valid oracle report to `handleOracleReport` which can be called by anyone **implementing this in current mock because of less possible chance of unintended errors**
			- or if the token is wrapped with an interface to make the `_mintShares` function public, it can be called directly
				- this could be simulated by finding the recipient in the shares mapping and modifying the stored value for their shares directly
	- [wbETH](https://bscscan.com/address/0xfe928a7d8be9c8cece7e97f0ed5704f4fa2cb42a#code)
		- wraps coinbase's StakedTokenV2 with extra functionality
		- when a user deposits ETH into the contract, they get minted wBETH
		- the oracle can update the exchange rate between wBETH => BETH by calling `updateExchangeRate` when rewards are received on the pooled staked ETH
			- this is an interest accrual rebasing mechanism, not an adjustment of the share supply
			- therefore to simulate a rebasing event, all that needs to be done is a privileged call to the `updateExchangeRate` function
			- expectation is that the exchange rate would be updated daily [from audit report](https://github.com/peckshield/publications/blob/master/audit_reports/PeckShield-Audit-Report-wBETHV2-v1.0.pdf)
			- the initial redemption rate between wBETH -> BETH is 1:1 from **2023-04-27 08:00 (UTC)** but wBETH gradually becomes more valuable as it accumulates rewards
			    - current exchange rate is: 1.040453033525