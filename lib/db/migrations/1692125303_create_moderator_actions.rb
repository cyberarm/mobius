Sequel.migration do
  change do
    create_table(:moderator_actions) do
      primary_key :id
      String :name, null: false
      String :ip, null: false
      String :serial, null: false
      String :moderator, null: false
      String :reason, null: false
      Integer :action, null: false

      Time :created_at
      Time :updated_at

      index :name
      index :ip
      index :serial
      index :moderator
      index :action
    end
  end
end