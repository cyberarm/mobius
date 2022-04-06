class Mobius
  class Results
    def initialize
      # Find lastest results file
      # Process it to find:
      @best_score   = 0
      @best_kills   = 0
      @worst_deaths = 0
      @best_kd      = 0.0

      process_results
    end

    def process_results
      file = find_last_results_file

      return unless file && File.exist?(file)
    end
  end
end
