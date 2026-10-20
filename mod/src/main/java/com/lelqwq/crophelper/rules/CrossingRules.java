package com.lelqwq.crophelper.rules;

import com.lelqwq.crophelper.catalog.Species;

/**
 * IC2 2.2.828 中 TileEntityCrop.calculateRatioFor 的逐行实现。
 *
 * <p>
 * 这里只接受目录快照，不访问世界，也不调用第三方 CropCard 的 canGrow/canCross，
 * 因此不会改变真实杂交结果，也不受工位环境影响。
 * </p>
 */
public final class CrossingRules {

    private CrossingRules() {}

    /** 候选品种相对于一个亲本的权重。 */
    public static int ratio(Species candidate, Species parent) {
        // IC2 使用对象引用判断同一品种；目录已保证 species_id 唯一，等价于 ID 相同。
        if (candidate.id.equals(parent.id)) {
            return 500;
        }

        int value = 0;
        for (int i = 0; i < 5; i++) {
            value += 2 - Math.abs(candidate.stat(i) - parent.stat(i));
        }

        // 与 IC2 一致：每个匹配的属性对都加 5，忽略大小写，重复标签会重复计数。
        String[] candidateAttributes = candidate.attributes();
        String[] parentAttributes = parent.attributes();
        for (String candidateAttribute : candidateAttributes) {
            for (String parentAttribute : parentAttributes) {
                if (candidateAttribute != null && parentAttribute != null
                    && candidateAttribute.equalsIgnoreCase(parentAttribute)) {
                    value += 5;
                }
            }
        }

        int tierDifference = candidate.tier - parent.tier;
        if (tierDifference > 1) {
            value -= 2 * tierDifference;
        }
        if (tierDifference < -3) {
            value += tierDifference;
        }
        return Math.max(value, 0);
    }

    /** 双亲本都已参与时，候选品种的完整权重（IC2 对每个参与亲本各调用一次）。 */
    public static int totalWeight(Species candidate, Species firstParent, Species secondParent) {
        return ratio(candidate, firstParent) + ratio(candidate, secondParent);
    }
}
