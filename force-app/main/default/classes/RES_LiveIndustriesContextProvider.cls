/** Production implementation - a thin delegate onto a real Context.IndustriesContext instance. */
public class RES_LiveIndustriesContextProvider implements RES_IndustriesContextProvider {
    private final Context.IndustriesContext ctx;

    public RES_LiveIndustriesContextProvider() {
        this.ctx = new Context.IndustriesContext();
    }

    public Map<String, Object> queryTags(Map<String, Object> queryInput) {
        return ctx.queryTags(queryInput);
    }

    public Object updateContextAttributes(Map<String, Object> updateInput) {
        return ctx.updateContextAttributes(updateInput);
    }
}
