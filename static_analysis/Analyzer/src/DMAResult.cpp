#include "DMAResult.h"

char DMAResult::ID = 0;
static llvm::RegisterPass<DMAResult> X("dma-result", "DMA Result Pass", false, true);
