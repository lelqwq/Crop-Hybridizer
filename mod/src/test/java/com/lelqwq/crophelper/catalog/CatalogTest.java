package com.lelqwq.crophelper.catalog;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.fail;

import java.util.Arrays;
import java.util.List;

import org.junit.Test;

import com.lelqwq.crophelper.ApiException;

public class CatalogTest {

    private static Species species(String owner, String name) {
        return new Species(owner, name, name, 1, new int[] { 1, 1, 1, 1, 1 }, new String[0], 4);
    }

    @Test
    public void sortsByIdAndPages() {
        Catalog catalog = new Catalog(
            Arrays.asList(species("B", "two"), species("A", "one"), species("C", "three")),
            "test");

        assertEquals(
            "A:one",
            catalog.species()
                .get(0).id);
        assertEquals(
            "B:two",
            catalog.species()
                .get(1).id);
        assertEquals(
            "C:three",
            catalog.species()
                .get(2).id);
        assertEquals(
            2,
            catalog.page(1, 2)
                .size());
        assertEquals(
            "B:two",
            catalog.page(1, 2)
                .get(0).id);
        assertEquals(
            "C:three",
            catalog.page(1, 2)
                .get(1).id);
        assertEquals(
            0,
            catalog.page(10, 2)
                .size());
    }

    @Test
    public void findsById() {
        Catalog catalog = new Catalog(Arrays.asList(species("A", "one"), species("B", "two")), "test");
        assertEquals("B:two", catalog.find("B:two").id);
        assertNull(catalog.find("B:missing"));
    }

    @Test
    public void rejectsDuplicateSpeciesId() {
        List<Species> duplicate = Arrays.asList(species("A", "one"), species("A", "one"));
        try {
            new Catalog(duplicate, "test");
            fail("expected ApiException");
        } catch (ApiException e) {
            assertEquals("query_failed", e.code());
        }
    }
}
