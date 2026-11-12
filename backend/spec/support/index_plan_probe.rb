# EXPLAIN checks that do not depend on the planner's statistics for the shared test tables.
#
# The tables of the test database are empty and never analyzed, so every candidate path costs the same and the planner may pick
# any index that matches. The probe clones the table (and its indexes) into a TEMP table owned by the test role, which can be
# ANALYZEd, fills it with a realistic history and EXPLAINs the statement the code really emitted against it.
module IndexPlanProbe
  module_function

  def connection = ActiveRecord::Base.connection

  # Definition of a real index without the name and the table, so it can be matched against its clone.
  def index_shape(table, name)
    definition = connection.select_value("SELECT indexdef FROM pg_indexes WHERE tablename = #{connection.quote(table)} AND indexname = #{connection.quote(name)}")
    definition.sub(/\A.* USING /, "")
  end

  # The EXPLAIN of `statement` (which reads `table`) run against a clone of `table` filled by `seed_sql` (which reads the clone's
  # name from {{clone}}), and the name the clone gave to the index shaped like `index_name`.
  def explain_on_clone(table:, statement:, index_name:, seed_sql:)
    clone = "tmp_#{table}"
    shape = index_shape(table, index_name)
    connection.execute("CREATE TEMP TABLE #{clone} (LIKE #{table} INCLUDING ALL) ON COMMIT DROP")
    connection.execute(seed_sql.gsub("{{clone}}", clone))
    connection.execute("ANALYZE #{clone}")
    cloned = connection.select_values("SELECT indexname FROM pg_indexes WHERE tablename = #{connection.quote(clone)}")
                       .find { |name| index_shape(clone, name) == shape }
    plan = connection.select_values("EXPLAIN #{statement.gsub("\"#{table}\"", "\"#{clone}\"")}").join("\n")
    [ plan, cloned ]
  end
end
