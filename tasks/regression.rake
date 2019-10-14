# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'mechanize'
require 'at_coder_friends'

module AtCoderFriends
  # tasks for regression test
  module Regression
    module_function

    CONTEST_LIST_URL = 'https://kenkoooo.com/atcoder/resources/contests.json'
    ACF_HOME = File.realpath(File.join(__dir__, '..'))
    REGRESSION_HOME = File.join(ACF_HOME, 'regression')
    PAGES_DIR = File.join(REGRESSION_HOME, 'pages')
    EMIT_ORG_DIR = File.join(REGRESSION_HOME, 'emit_org')
    EMIT_DIR_FMT = File.join(REGRESSION_HOME, 'emit_%<now>s')

    def setup
      rmdir_force(PAGES_DIR)
      rmdir_force(EMIT_ORG_DIR)
      contest_id_list.each do |contest|
        begin
          ctx = context(EMIT_ORG_DIR, contest)
          ctx.scraping_agent.fetch_all do |pbm|
            begin
              html_path = File.join(PAGES_DIR, contest, "#{pbm.q}.html")
              save_file(html_path, pbm.page.body)
              pipeline(ctx, pbm)
            rescue StandardError => e
              p e
            end
          end
        rescue StandardError => e
          p e
        end
        sleep 3
      end
    end

    def check_diff
      emit_dir = format(EMIT_DIR_FMT, now: Time.now.strftime('%Y%m%d%H%M%S'))
      rmdir_force(emit_dir)

      local_pbm_list.each do |contest, q, url|
        ctx = context(emit_dir, contest)
        pbm = ctx.scraping_agent.fetch_problem(q, url)
        pipeline(ctx, pbm)
      end

      system("diff -r #{EMIT_ORG_DIR} #{emit_dir}")
    end

    def section_list
      agent = Mechanize.new
      list = local_pbm_list.flat_map do |contest, q, url|
        page = agent.get(url)
        %w[h2 h3].flat_map do
          page.search('h3').map do |h3|
            { contest: contest, q: q, text: normalize(h3.content) }
          end
        end
      end
      list.group_by { |sec| sec[:text] }.each do |k, vs|
        puts [k, vs.size, vs[0][:contest], vs[0][:q]].join("\t")
      end
    end

    def check_parse
      parse_list
        .select { |_, _, no_fmt, no_smp| no_fmt || no_smp }
        .map { |c, q, no_fmt, no_smp| [c, q, f_to_s(no_fmt), f_to_s(no_smp)] }
        .sort
        .each { |args| puts args.join("\t") }
    end

    def parse_list
      local_pbm_list.map do |contest, q, url|
        ctx = context('', contest)
        pbm = ctx.scraping_agent.fetch_problem(q, url)
        Parser::Main.process(pbm)
        no_fmt = pbm.fmt.empty?
        no_smp = pbm.smps.all? { |smp| smp.txt.empty? }
        [contest, q, no_fmt, no_smp]
      end
    end

    def f_to_s(f)
      f ? '◯' : '-'
    end

    def contest_id_list
      uri = URI.parse(CONTEST_LIST_URL)
      json = Net::HTTP.get(uri)
      contests = JSON.parse(json)
      puts "Total #{contests.size} contests"
      contests.map { |h| h['id'] }
    end

    def local_pbm_list
      Dir.glob(PAGES_DIR + '/**/*.html').map do |pbm_path|
        contest = File.basename(File.dirname(pbm_path))
        q = File.basename(pbm_path, '.html')
        url = "file://#{pbm_path}"
        [contest, q, url]
      end
    end

    def context(root, contest)
      Context.new({}, File.join(root, contest))
    end

    def rmdir_force(dir)
      FileUtils.rm_r(dir) if Dir.exist?(dir)
    end

    def save_file(path, content)
      dir = File.dirname(path)
      FileUtils.makedirs(dir) unless Dir.exist?(dir)
      File.binwrite(path, content)
    end

    def pipeline(ctx, pbm)
      @rb_gen ||= RubyGenerator.new
      @cxx_gen ||= CxxGenerator.new
      Parser::Main.process(pbm)
      @rb_gen.process(pbm)
      @cxx_gen.process(pbm)
      ctx.emitter.emit(pbm)
    end

    def normalize(s)
      s
        .tr('　０-９Ａ-Ｚａ-ｚ', ' 0-9A-Za-z')
        .gsub(/[^一-龠_ぁ-ん_ァ-ヶーa-zA-Z0-9 ]/, '')
        .strip
    end
  end
end

namespace :regression do
  desc 'setup regression environment'
  task :setup do
    AtCoderFriends::Regression.setup
  end

  desc 'run regression check'
  task :check_diff do
    AtCoderFriends::Regression.check_diff
  end

  desc 'list all section titles'
  task :section_list do
    AtCoderFriends::Regression.section_list
  end

  desc 'checks page parse result'
  task :check_parse do
    AtCoderFriends::Regression.check_parse
  end
end