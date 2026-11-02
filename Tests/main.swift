import Foundation

func require(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}

var gate = UnlockGesture()
gate.keyDown(isUnlockKey: true, modifiersMatch: false, isRepeat: false, at: 0)
require(!gate.isComplete(at: 20), "K without the complete chord must not unlock")
gate.keyDown(isUnlockKey: true, modifiersMatch: true, isRepeat: false, at: 30)
require(!gate.isComplete(at: 31.9), "A short hold must not unlock")
gate.keyDown(isUnlockKey: true, modifiersMatch: true, isRepeat: true, at: 31.5)
require(gate.isComplete(at: 32), "Auto-repeat must not reset the hold timer")
gate.keyUp(isUnlockKey: true)
require(!gate.isComplete(at: 40), "Releasing K must cancel the hold")
gate.keyDown(isUnlockKey: true, modifiersMatch: true, isRepeat: false, at: 50)
gate.modifiersChanged(match: false)
require(!gate.isComplete(at: 60), "Releasing a modifier must cancel the hold")
gate.keyDown(isUnlockKey: true, modifiersMatch: true, isRepeat: false, at: 70)
gate.keyDown(isUnlockKey: false, modifiersMatch: true, isRepeat: false, at: 71)
require(!gate.isComplete(at: 75), "Another key must cancel an in-progress gesture")
gate.keyDown(isUnlockKey: true, modifiersMatch: true, isRepeat: false, at: 80)
require(gate.isComplete(at: 82), "The complete sustained chord must unlock")
print("Unlock gesture checks passed")
