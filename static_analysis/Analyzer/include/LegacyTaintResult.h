#ifndef _LEGACY_TAINT_RESULT_H_
#define _LEGACY_TAINT_RESULT_H_

#include "common.h"
#include "llvm/Pass.h"

class DMATaintResult : public llvm::ImmutablePass {
public:
	static char ID;
	DMATaintResult() : llvm::ImmutablePass(ID) {}

	void setResult(DeviceInfo res) {
		result = res;
	}
	DeviceInfo getResult() const {
		return result;
	}

private:
	DeviceInfo result;
};

#endif
