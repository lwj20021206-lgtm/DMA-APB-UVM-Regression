#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd -- "$script_dir/.." && pwd)

directed_tests=${DIRECTED_TESTS:-"dma_apb_smoke_test dma_apb_register_direct_test dma_apb_init_test dma_apb_copy_test dma_apb_interrupt_test dma_apb_target_wait_test dma_apb_busy_test dma_apb_reset_test"}
random_seeds=${RANDOM_SEEDS:-"1 2 3 4 5"}
random_ops=${RANDOM_OPS:-40}

echo "Running directed DMA/APB tests"
for test_name in $directed_tests; do
  echo "  TEST=$test_name SEED=1"
  make --no-print-directory -C "$project_root" run-only \
    TEST="$test_name" SEED=1 RANDOM_OPS="$random_ops"
done

echo "Running constrained-random DMA/APB tests"
for random_seed in $random_seeds; do
  echo "  TEST=dma_apb_random_test SEED=$random_seed"
  make --no-print-directory -C "$project_root" run-only \
    TEST=dma_apb_random_test SEED="$random_seed" \
    RANDOM_OPS="$random_ops"
done

echo "Regression runs completed"
