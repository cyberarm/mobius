Sequel.migration do
  change do
    create_table(:ips) do
      primary_key :id
      String :name, null: false
      String :ip, null: false

      DataTime :created_at
      DataTime :updated_at

      index :name
      index :ip
    end
  end
end