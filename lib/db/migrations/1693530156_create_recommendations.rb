Sequel.migration do
  change do
    create_table(:recommendations) do
      primary_key :id
      String  :recommender_name, null: false
      String  :player_name, null: false
      String  :comment, null: false
      Boolean :noob, default: false

      Time :created_at
      Time :updated_at

      index :recommender_name
      index :player_name
      index :noob
    end

    create_table(:recommendation_counter_cache) do
      primary_key :id
      String  :player_name, null: false
      Integer :recommendations, default: 0
      Integer :noobs, default: 0

      Time :created_at
      Time :updated_at

      index :player_name
    end
  end
end