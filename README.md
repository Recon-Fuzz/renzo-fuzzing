## Renzo Fuzzing

Fuzzing harness provided by Recon, located in test/recon. Learn more about the standard Recon harness [here](https://getrecon.substack.com/p/building-a-test-harness-with-recon?r=34r2zr) 

### System Setup

This suite integrates a full local deployment of the EigenLayer system (provided by this [repo](https://github.com/nican0r/eigenlayer-fuzzing/tree/main))with a fuzzing scaffolding of the Renzo system to test invariants defined for Renzo.

The EigenLayer system is added as a dependency in the eigenlayer-fuzzing submodule. 

To deploy the EigenLayer system in RenzoSetup it inherits from the  EigenLayerSystem contract and calls the `deployEigenLayerLocal` function, allowing access to all EigenLayer contracts within the target function contracts, and subsequently direct manipulation of the EigenLayer state. 

Clamping has been applied for certain target functions to limit the fuzzer search space to values actually used within system, this is primarily done via `_getRandomDepositableToken` and `_getRandomOperatorDelegator`, which prevent reverts for uninteresting reasons, such as an address input for a token which is not set as a collateral token in RestakeManager. 

### Externalities 

The following externalities that may have side-effects within the Renzo system have been implemented to facilitate more realistic fuzzing of these types of events:

- [Native ETH slashing](https://github.com/nican0r/renzo-fuzzing/blob/4364ec80cce740bbafb09be1aab8929faf3e1c96/test/recon/RestakeManagerTargets.sol#L120-L124)
- [AVS slashing](https://github.com/nican0r/renzo-fuzzing/blob/4364ec80cce740bbafb09be1aab8929faf3e1c96/test/recon/RestakeManagerTargets.sol#L127-L135)
- [LST discounting](https://github.com/nican0r/renzo-fuzzing/blob/4364ec80cce740bbafb09be1aab8929faf3e1c96/test/recon/RestakeManagerTargets.sol#L138-L152)
- [LST rebasing](https://github.com/nican0r/renzo-fuzzing/blob/4364ec80cce740bbafb09be1aab8929faf3e1c96/test/recon/RestakeManagerTargets.sol#L156-L172)

These have all been implemented as target functions in the RestakManagerTargetFunctions contract, and therefore will automatically called in the default fuzz testing setup.

For more detail on the implementation and design decisions behind each, see the [externalities.md](https://github.com/nican0r/renzo-fuzzing/blob/main/externalities.md) file.

### Setup

```bash
git clone --recurse-submodules https://github.com/nican0r/renzo-fuzzing
npm install
forge install
```

### Fuzzing with Echidna
```bash
echidna . --contract CryticTester --config echidna.yaml
```

### Fuzzing with Medusa
```
medusa fuzz
```
