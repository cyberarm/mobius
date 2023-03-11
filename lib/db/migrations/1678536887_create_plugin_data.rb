Sequel.migration do
  change do
    create_table(:plugin_data) do
      primary_key :id
      String :plugin_name, null: false
      String :key, null: false
      Text   :value, null: false

      Time :created_at
      Time :updated_at

      index :plugin_name
      index :key
    end
  end
end