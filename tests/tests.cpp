#include <gtest/gtest.h>

#include <vector>
#include <unordered_set>

namespace tests
{
    [[nodiscard]] bool grouped(std::vector<size_t>* indices)
    {
        assert(!indices->empty());
        size_t currentIndex = indices->at(0);

        std::unordered_set<size_t> foundIndices;

        for (auto& index: *indices)
        {
            if (index != currentIndex)
            {
                if (foundIndices.contains(index))
                {
                    return false;
                }
                else
                {
                    foundIndices.emplace(index);
                }
            }
            currentIndex = index;
        }

        return true;
    }

    TEST(Tests, Grouped)
    {
        std::vector<size_t> indicesNotGrouped = {0, 0, 0, 0, 5, 5, 5, 5, 5, 2, 2, 2, 5};
        ASSERT_FALSE(grouped(&indicesNotGrouped));

        std::vector<size_t> indicesGrouped = {1, 1, 1, 1, 6, 6, 6, 6, 6, 3, 2, 2, 2, 2};
        ASSERT_TRUE(grouped(&indicesGrouped));

        std::vector<size_t> indicesGrouped2 = {9, 8, 5, 5, 5, 5, 5, 3, 2, 1, 0, 10, 10, 10};
        ASSERT_TRUE(grouped(&indicesGrouped2));
    }
}