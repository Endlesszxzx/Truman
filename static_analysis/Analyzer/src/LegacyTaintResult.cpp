#include "LegacyTaintResult.h"

char DMATaintResult::ID = 0;
static llvm::RegisterPass<DMATaintResult> Y("dma-taint-result", "DMA Taint Result Pass", false, true);
