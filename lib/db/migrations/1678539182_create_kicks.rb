Sequel.migration do
  change do
    create_table(:kicks) do
      primary_key :id
      String :name, null: false
      String :ip, null: false
      String :serial, null: false
      String :banner, null: false
      String :reason, null: false

      DataTime :created_at
      DataTime :updated_at

      index :name
      index :ip
      index :serial
      index :banner
    end
  end
end