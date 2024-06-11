## EigenLayer Externalities

### Native ETH Slashing
Replicating this by burning the ETH associated with a validator in the `ETHDepositMock` contract by introducing a `slash` function (takes in a given amount to slash and burns the corresponding ETH in the contract to the 0 address) and updating the `EigenPodManager` accounting for the `OperatorDelegator` that staked the ETH.  

This is implemented in `RestakManagerTagetsV2::restakeManager_slash_native`. 

### AVS Slashing
AVS slashing hasn't been implemented in EigenLayer yet so the implementation defined in `RestakManagerTagetsV2::restakeManager_slash_AVS` is an interpretation of what the EigenLayer `Slasher` may eventually implement by inferring how the `recordStakeUpdate` defined in the [current `Slasher` interface](https://github.com/Layr-Labs/eigenlayer-contracts/blob/f3aa0efc2be0013b5002444b74ef7413e1779f59/src/contracts/core/Slasher.sol#L47) may behave. 

The primary mechanism of implemented function is to reduce a percentage of an OperatorDelegator's stake (representing their slashed amount) by burning it and updating their accounting in `EigenPodManager` (native ETH) or `StrategyManager` (LST tokens) to reflect this burnt amount. 

The decision was made to reduce a given OperatorDelegator's stake by 3% as this is roughly the same as the ratio of the maximum slashing penalty in native ETH slashing (1/32 ETH), however this should be updated if the released EigenLayer `Slasher` implementation behaves differently. Using a percentage instead of a fixed value (like 1 ETH) was also necessary because the OperatorDelegator's staked amount is variable and therefore makes it not well suited for slashing as by a fixed amount. 

Note that unlike the native ETH slashing implemented in `restakeManager_slash_native` where only an individual validator owned by the OperatorDelegator is slashed, in this implementation if the OperatorDelegator owns multiple validators, they're all collectively slashed by 3%. This seems like it would be a logical penalty applied by EigenLayer since AVS slashing is meant to punish Operators that misbehave, and since in the Renzo system each OperatorDelegator corresponds to 1 Operator, a slash on the Operator would apply over all the Operator's validators.

The following are the only cases that the EigenLayer system would have an effect on balances via slashing, other cases where an amount is deposited but held in a queue would essentially be invisible to EigenLayer and therefore aren't covered in the tests since they would be unaffected by an AVS slashing event:
    - Native ETH: OperatorDelegator has created a validator with the staked ETH (at least 32 ETH deposited)
    - LSTs: OperatorDelegator has received deposits greater than the withdrawQueue buffer amount
    
### LST Discounting
LST discounting would be due to a depegging event between the price of the LST token and the underlying staked ETH. The function implemented to mimic this in `RestakManagerTagetsV2::restakeManager_LST_discount` modifies the oracle price using the most recent price by discounting it up to 500 basis points. 

500 basis points is used as a maximum discount to the price based on historical data for stETH described here: https://medium.com/huobi-research/steth-depegging-what-are-the-consequences-20b4b7327b0c. 

This implementation is currently tightly coupled with the ability to set the price in the oracle since the current setup uses a mock for it. When implementing this for a forked testing setup will need to most likely implement something similar to what was done in eBTC where the storage variable representing price is directly overwritten. 