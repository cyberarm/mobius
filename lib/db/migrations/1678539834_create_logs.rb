Sequel.migration do
  change do
    create_table(:logs) do
      primary_key :id
      Integer :log_code, null: false
      String  :log, null: false

      Time :created_at
      Time :updated_at

      index :log_code
    end
  end
end