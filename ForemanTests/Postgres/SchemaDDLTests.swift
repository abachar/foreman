import Testing

@testable import Foreman

/// postgres R8: the DDL reconstructed from hand-built catalog rows.
struct SchemaDDLTests {
    @Test func tableListsColumnsConstraintsAndStandaloneIndexes() {
        let ddl = SchemaDDL.table(
            schema: "public", name: "order",
            columns: [
                SchemaNode.Column(name: "id", type: "integer", isNotNull: true, defaultValue: nil, isPrimaryKey: true),
                SchemaNode.Column(
                    name: "Name", type: "character varying(255)", isNotNull: false, defaultValue: "'x'::text",
                    isPrimaryKey: false),
            ],
            constraints: [
                SchemaDDL.Definition(name: "order_pkey", text: "PRIMARY KEY (id)"),
                SchemaDDL.Definition(name: "order_user_fkey", text: "FOREIGN KEY (user_id) REFERENCES users(id)"),
            ],
            indexes: [
                SchemaDDL.Definition(
                    name: "order_pkey", text: "CREATE UNIQUE INDEX order_pkey ON public.\"order\" USING btree (id)"),
                SchemaDDL.Definition(
                    name: "order_name_idx",
                    text: "CREATE INDEX order_name_idx ON public.\"order\" USING btree (\"Name\")"),
            ])
        #expect(
            ddl == """
                CREATE TABLE "public"."order" (
                    "id" integer NOT NULL,
                    "Name" character varying(255) DEFAULT 'x'::text,
                    CONSTRAINT "order_pkey" PRIMARY KEY (id),
                    CONSTRAINT "order_user_fkey" FOREIGN KEY (user_id) REFERENCES users(id)
                );
                CREATE INDEX order_name_idx ON public."order" USING btree ("Name");
                """)
    }

    @Test func viewWrapsTheServerDefinition() {
        #expect(
            SchemaDDL.view(schema: "public", name: "v", isMaterialized: false, definition: " SELECT 1;\n")
                == "CREATE OR REPLACE VIEW \"public\".\"v\" AS\nSELECT 1;")
        #expect(
            SchemaDDL.view(schema: "public", name: "m", isMaterialized: true, definition: "SELECT 1")
                == "CREATE MATERIALIZED VIEW \"public\".\"m\" AS\nSELECT 1;")
    }
}
