## Renzo Fuzzing

Fuzzing harness provided by Recon, located in test/recon.

### System Setup

This suite integrates a full local deployment of the EigenLayer system with a fuzzing scaffolding of the Renzo system to test invariants defined for Renzo.

The EigenLayer system is added as a dependency in the eigenlayer-fuzzing submodule. 

To deploy the EigenLayer system in RenzoSetup it inherits from the  EigenLayerSystem contract and calls the `deployEigenLayerLocal` function, allowing access to all EigenLayer contracts within the target function contracts, and subsequently direct manipulation of the EigenLayer state. 

Clamping has been applied for certain target functions to limit the fuzzer search space to values actually used within system, this is primarily done via `_getRandomDepositableToken` and `_getRandomOperatorDelegator`, which prevent reverts for uninteresting reasons, such as an address input for a token which is not set as a collateral token in RestakeManager. 

### Externalities 

The following externalities that may have side-effects within the Renzo system have been implemented to facilitate more realistic fuzzing of these types of events:

- Native ETH slashing
- AVS slashing
- LST discounting 
- LST rebasing

These have all been implemented as target functions in the RestakManagerTargetFunctions contract, and therefore will automatically called in the default fuzz testing setup.

For more detail on the implementation and design decisions behind each, see the externalities.md file.

### Setup

```bash
git clone --recurse-submodules https://github.com/nican0r/renzo-fuzzing
npm install
forge install
```