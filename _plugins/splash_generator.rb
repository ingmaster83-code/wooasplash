require 'json'

module Jekyll
  class SplashPageGenerator < Generator
    safe true
    priority :normal

    TIDE_MAX_DIST_DEG = 0.5 # 대략 50km 이내일 때만 연결

    def generate(site)
      spots = site.data['splash_spots']
      return unless spots&.any?

      tide_spots = site.data['tide_lookup'] || []

      Jekyll.logger.info "SplashGenerator:", "#{spots.size}개 페이지 생성 중..."

      spots.each do |spot|
        same_region = spots
          .select { |s| s['region'] == spot['region'] && s['slug'] != spot['slug'] }
          .first(8)
          .map { |s| { 'slug' => s['slug'], 'name' => s['spotName'], 'city' => s['city'], 'kindLabel' => s['kindLabel'], 'kindIcon' => s['kindIcon'], 'image' => s['image'] } }

        same_kind = spots
          .select { |s| s['kind'] == spot['kind'] && s['slug'] != spot['slug'] }
          .first(8)
          .map { |s| { 'slug' => s['slug'], 'name' => s['spotName'], 'region' => s['region'], 'city' => s['city'], 'image' => s['image'] } }

        # 이전/다음: 같은 지역 내에서 유형 -> 이름 순 정렬 후 순환
        region_ordered = spots
          .select { |s| s['region'] == spot['region'] }
          .sort_by { |s| [s['kind'].to_s, s['spotName'].to_s] }
        idx = region_ordered.index { |s| s['slug'] == spot['slug'] }
        prev_spot = nil
        next_spot = nil
        if idx && region_ordered.size > 1
          p = region_ordered[(idx - 1) % region_ordered.size]
          n = region_ordered[(idx + 1) % region_ordered.size]
          prev_spot = { 'slug' => p['slug'], 'name' => p['spotName'] }
          next_spot = { 'slug' => n['slug'], 'name' => n['spotName'] }
        end

        site.pages << SplashSpotPage.new(site, spot, same_region, same_kind, prev_spot, next_spot, nearest_tide_spot(spot, tide_spots))
      end

      by_region = spots.group_by { |s| s['region'] }
      by_region.each do |region, region_spots|
        slug = region_spots.first['regionSlug']
        site.pages << RegionPage.new(site, region, slug, region_spots)
      end

      by_kind = spots.group_by { |s| s['kind'] }
      by_kind.each do |kind, kind_spots|
        site.pages << KindPage.new(site, kind, kind_spots)
      end

      site.pages << SearchIndexPage.new(site, spots)

      Jekyll.logger.info "SplashGenerator:", "완료 (#{spots.size}개)"
    end

    def nearest_tide_spot(spot, tide_spots)
      return nil unless spot['kind'] == 'beach'
      return nil if spot['lat'].to_s.empty? || spot['lng'].to_s.empty? || tide_spots.empty?

      s_lat = spot['lat'].to_f
      s_lng = spot['lng'].to_f
      best, best_d = nil, nil
      tide_spots.each do |t|
        d = (t['lat'].to_f - s_lat)**2 + (t['lot'].to_f - s_lng)**2
        best, best_d = t, d if best_d.nil? || d < best_d
      end
      return nil if best.nil? || Math.sqrt(best_d) > TIDE_MAX_DIST_DEG
      best
    end
  end

  class SplashSpotPage < Page
    def initialize(site, spot, same_region, same_kind, prev_spot, next_spot, nearest_tide = nil)
      @site = site
      @base = site.source
      @dir  = "spot/#{spot['slug']}"
      @name = 'index.html'

      self.process(@name)
      self.read_yaml(File.join(@base, '_layouts'), 'splashspot.html')
      self.data.merge!(spot)
      self.data['layout']      = 'splashspot'
      self.data['same_region'] = same_region
      self.data['same_kind']   = same_kind
      self.data['prev_spot']   = prev_spot
      self.data['next_spot']   = next_spot
      self.data['nearestTide'] = nearest_tide

      self.data['title'] = "#{spot['spotName']} 위치·이용시간·주차정보 | #{spot['region']} #{spot['city']} #{spot['kindLabel']}"
      overview_short = (spot['overview'] || '').to_s
      overview_short = overview_short[0, 80] unless overview_short.empty?
      self.data['description'] = "#{spot['spotName']}(#{spot['region']} #{spot['city']}) #{spot['kindLabel']} 정보. #{overview_short}"
    end
  end

  class RegionPage < Page
    def initialize(site, region, slug, spots)
      @site = site
      @base = site.source
      @dir  = "region/#{slug}"
      @name = 'index.html'

      self.process(@name)
      self.read_yaml(File.join(@base, '_layouts'), 'region.html')
      self.data['layout']      = 'region'
      self.data['region']      = region
      self.data['region_slug'] = slug
      self.data['spots']       = spots
      self.data['title']       = "#{region} 해수욕장·계곡 총정리 | 여름 물놀이 명소 #{spots.size}곳"
      self.data['description'] = "#{region} 해수욕장·계곡 #{spots.size}곳 총정리! 위치·이용시간·주차정보를 한눈에 확인하세요."
    end
  end

  class KindPage < Page
    def initialize(site, kind, spots)
      @site = site
      @base = site.source
      @dir  = "kind/#{kind}"
      @name = 'index.html'

      label = kind == 'beach' ? '해수욕장' : '계곡'
      icon = kind == 'beach' ? '🏖️' : '🏞️'

      self.process(@name)
      self.read_yaml(File.join(@base, '_layouts'), 'kind.html')
      self.data['layout']     = 'kind'
      self.data['kind_slug']  = kind
      self.data['kind_label'] = label
      self.data['kind_icon']  = icon
      self.data['spots']      = spots
      self.data['title']       = "전국 #{label} 목록 #{spots.size}곳"
      self.data['description'] = "전국 #{label} #{spots.size}곳 목록. 지역별 #{label} 정보를 확인하세요."
    end
  end

  class SearchIndexPage < Page
    def initialize(site, spots)
      @site = site
      @base = site.source
      @dir  = ''
      @name = 'search_index.json'

      self.process(@name)
      self.data = { 'layout' => nil, 'sitemap' => false }

      index = spots.map do |s|
        {
          'slug' => s['slug'], 'name' => s['spotName'], 'region' => s['region'], 'city' => s['city'],
          'kindLabel' => s['kindLabel'], 'image' => s['image'],
        }
      end

      self.content = index.to_json
    end

    def output   = self.content
    def render(layouts, registers); end
  end
end
