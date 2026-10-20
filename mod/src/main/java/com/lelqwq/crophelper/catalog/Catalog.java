package com.lelqwq.crophelper.catalog;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import com.lelqwq.crophelper.ApiException;
import com.lelqwq.crophelper.util.Fingerprint;

/**
 * 某一时刻的作物目录快照，按稳定的 species_id 排序，附带规则指纹。
 */
public final class Catalog {

    private final List<Species> species;
    private final Map<String, Species> byId;
    private final String fingerprint;

    public Catalog(List<Species> input, String modVersions) {
        List<Species> sorted = new ArrayList<Species>(input);
        Collections.sort(sorted, new Comparator<Species>() {

            @Override
            public int compare(Species left, Species right) {
                return left.id.compareTo(right.id);
            }
        });

        Set<String> ids = new HashSet<String>();
        for (Species value : sorted) {
            if (!ids.add(value.id)) {
                throw new ApiException("query_failed", "duplicate species_id: " + value.id);
            }
        }

        Map<String, Species> index = new HashMap<String, Species>();
        for (Species value : sorted) {
            index.put(value.id, value);
        }

        this.species = Collections.unmodifiableList(sorted);
        this.byId = Collections.unmodifiableMap(index);
        this.fingerprint = Fingerprint.compute(sorted, modVersions);
    }

    public List<Species> species() {
        return species;
    }

    public Species find(String speciesId) {
        return byId.get(speciesId);
    }

    public int size() {
        return species.size();
    }

    public String fingerprint() {
        return fingerprint;
    }

    /** 返回 [offset, offset + limit) 范围内的品种；越界时返回空列表。 */
    public List<Species> page(int offset, int limit) {
        if (offset >= species.size()) {
            return Collections.emptyList();
        }
        long end = (long) offset + limit;
        int to = end > species.size() ? species.size() : (int) end;
        return species.subList(offset, to);
    }
}
