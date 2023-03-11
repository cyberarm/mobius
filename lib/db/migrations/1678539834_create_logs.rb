Sequel.migration do
  change do
    create_table(:logs) do
      primary_key :id
      Integer :log_code, null: false
      String  :log, null: false

      DataTime :created_at
      DataTime :updated_at

      index :log_code
    end
  end
end