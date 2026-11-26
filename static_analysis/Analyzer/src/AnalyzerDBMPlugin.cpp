#include "dma.h"
#include "dma_analysis.h"

#include "llvm/Config/llvm-config.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"

namespace {

class AnalyzerDBMPipelinePass : public llvm::PassInfoMixin<AnalyzerDBMPipelinePass> {
public:
	llvm::PreservedAnalyses run(llvm::Module &module,
			llvm::ModuleAnalysisManager &) {
		llvm::legacy::PassManager legacy_pass_manager;
		legacy_pass_manager.add(new DMAPass());
		legacy_pass_manager.add(new DRCHECKER::DMAAnalysisPass());
		legacy_pass_manager.run(module);
		return llvm::PreservedAnalyses::all();
	}
};

}  // namespace

extern "C" LLVM_ATTRIBUTE_WEAK llvm::PassPluginLibraryInfo llvmGetPassPluginInfo() {
	return {
		LLVM_PLUGIN_API_VERSION,
		"AnalyzerDBM",
		LLVM_VERSION_STRING,
		[](llvm::PassBuilder &pass_builder) {
			pass_builder.registerPipelineParsingCallback(
				[](llvm::StringRef name, llvm::ModulePassManager &module_pass_manager,
						llvm::ArrayRef<llvm::PassBuilder::PipelineElement>) {
					if (name != "truman-dbm") {
						return false;
					}
				module_pass_manager.addPass(AnalyzerDBMPipelinePass());
				return true;
				});
		}
	};
}
