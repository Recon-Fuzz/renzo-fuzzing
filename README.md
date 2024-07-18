## Renzo Fuzzing

This repo is based around a fuzzing harness built with Recon, located in the test/recon directory to allow testing properties of the Renzo system. 

Learn more about the standard Recon harness [here](https://getrecon.substack.com/p/building-a-test-harness-with-recon?r=34r2zr) 

### System Setup

This suite integrates a full local deployment of the EigenLayer system (provided by this [repo](https://github.com/Recon-Fuzz/eigenlayer-fuzzing/tree/main)) with a fuzzing scaffolding of the Renzo system to test Renzo invariants.

The EigenLayer system is added as a dependency in the eigenlayer-fuzzing submodule. 

To deploy the EigenLayer system in RenzoSetup it inherits from the `EigenLayerSystem` contract and calls the `deployEigenLayerLocal` function, allowing access to all EigenLayer contracts for setting up Renzo without any mocks, subsequently the EigenLayer system state can be directly manipulated for testing edge cases, as is described in the Externalities section. 

Clamping has been applied for certain target functions to limit the fuzzer search space to values actually used within system, this is primarily done via `_getRandomDepositableToken` and `_getRandomOperatorDelegator`, which prevent reverts for uninteresting reasons, such as an address input for a token which is not set as a collateral token in `RestakeManager`. 

### Externalities 

The following externalities that may have side-effects within the Renzo system have been implemented to facilitate more realistic fuzzing of these types of events:

- [Native ETH slashing](https://github.com/Recon-Fuzz/renzo-fuzzing/blob/4364ec80cce740bbafb09be1aab8929faf3e1c96/test/recon/RestakeManagerTargets.sol#L120-L124)
- [AVS slashing](https://github.com/Recon-Fuzz/renzo-fuzzing/blob/4364ec80cce740bbafb09be1aab8929faf3e1c96/test/recon/RestakeManagerTargets.sol#L127-L135)
- [LST discounting](https://github.com/Recon-Fuzz/renzo-fuzzing/blob/4364ec80cce740bbafb09be1aab8929faf3e1c96/test/recon/RestakeManagerTargets.sol#L138-L152)
- [LST rebasing](https://github.com/Recon-Fuzz/renzo-fuzzing/blob/4364ec80cce740bbafb09be1aab8929faf3e1c96/test/recon/RestakeManagerTargets.sol#L156-L172)

These have all been implemented as target functions in the `RestakManagerTargetFunctions` contract, and therefore will automatically be called in the default fuzz testing setup.

For more detail on the implementation and design decisions behind each, see the [externalities.md](https://github.com/Recon-Fuzz/renzo-fuzzing/blob/main/externalities.md) file.

### Setup

```bash
git clone --recurse-submodules https://github.com/Recon-Fuzz/renzo-fuzzing
npm install
forge install
```
## Fuzzing 
Because this repo has been scaffolded with Recon, it automatically works for running jobs using Recon's cloud runner. 

For an example 12hr job run with Medusa, see [here](https://getrecon.xyz/shares/954343b5-87e7-4822-8e3f-b0414723121d)

### Fuzzing with Echidna
```bash
echidna . --contract CryticTester --config echidna.yaml
```

### Fuzzing with Medusa
```
medusa fuzz
```
