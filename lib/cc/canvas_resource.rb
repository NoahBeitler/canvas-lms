# frozen_string_literal: true

#
# Copyright (C) 2011 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#
module CC
  module CanvasResource
    include ModuleMeta
    include ExternalFeeds
    include AssignmentGroups
    include GradingStandards
    include LatePolicy
    include LearningOutcomes
    include Rubrics
    include Events
    include CoursePaces
    include BlueprintSettings
    include WebResources

    def add_canvas_non_cc_data
      migration_id = create_key(@course)

      @canvas_resource_dir = File.join(@export_dir, CCHelper::COURSE_SETTINGS_DIR)
      canvas_export_path = File.join(CCHelper::COURSE_SETTINGS_DIR, CCHelper::CANVAS_EXPORT_FLAG)
      FileUtils.mkdir_p @canvas_resource_dir

      resources = []
      resources << run_and_set_progress(:create_course_settings, nil, I18n.t("course_exports.errors.course_settings", "Failed to export course settings"), migration_id) if export_symbol?(:all_course_settings)
      resources << run_and_set_progress(:create_module_meta, nil, I18n.t("course_exports.errors.module_meta", "Failed to export module meta data"))
      resources << run_and_set_progress(:create_course_paces, nil, I18n.t("Failed to export course paces"))
      resources << run_and_set_progress(:create_external_feeds, nil, I18n.t("course_exports.errors.external_feeds", "Failed to export external feeds"))
      resources << run_and_set_progress(:create_assignment_groups, nil, I18n.t("course_exports.errors.assignment_groups", "Failed to export assignment groups"))
      resources << run_and_set_progress(:create_grading_standards, 20, I18n.t("course_exports.errors.grading_standards", "Failed to export grading standards"))
      resources << run_and_set_progress(:create_rubrics, nil, I18n.t("course_exports.errors.rubrics", "Failed to export rubrics"))
      resources << run_and_set_progress(:create_learning_outcomes, nil, I18n.t("course_exports.errors.learning_outcomes", "Failed to export learning outcomes"))
      resources << run_and_set_progress(:files_meta_path, nil, I18n.t("course_exports.errors.file_meta", "Failed to export file meta data"))
      resources << run_and_set_progress(:create_events, 25, I18n.t("course_exports.errors.events", "Failed to export calendar events"))
      resources << run_and_set_progress(:add_late_policy, nil, I18n.t("course_exports.errors.late_policy", "Failed to export late policy")) if export_symbol?(:all_course_settings)
      resources << run_and_set_progress(:create_context_info, nil, I18n.t("Failed to export context info")) unless @content_export&.for_course_copy?

      if export_media_objects?
        File.write(File.join(@canvas_resource_dir, CCHelper::MEDIA_TRACKS), "") # just in case an error happens later
        resources << File.join(CCHelper::COURSE_SETTINGS_DIR, CCHelper::MEDIA_TRACKS)
      end

      # Create the syllabus resource
      if @course.syllabus_body && (export_symbol?(:syllabus_body) || export_symbol?(:all_syllabus_body))
        syl_rel_path = create_syllabus
        @resources.resource(
          :identifier => migration_id + "_syllabus",
          "type" => Manifest::LOR,
          :href => syl_rel_path,
          :intendeduse => "syllabus"
        ) do |res|
          res.file(href: syl_rel_path)
        end
      end

      create_canvas_export_flag

      # Create other resources
      @resources.resource(
        :identifier => migration_id,
        "type" => Manifest::LOR,
        :href => canvas_export_path
      ) do |res|
        resources.each do |resource|
          res.file(href: resource) if resource
        end

        res.file(href: canvas_export_path)
      end
    end

    # Method Summary
    #   The canvas export flag is just a txt file we can use to
    #   verify this is a canvas flavor of common cartridge. We
    #   do this because we can't change the structure of the xml
    #   but still need some type of flag.
    def create_canvas_export_flag
      path = File.join(@canvas_resource_dir, "canvas_export.txt")
      canvas_export_file = File.open(path, "w")

      # Fun panda joke!
      canvas_export_file << <<~TEXT
        Q: What did the panda say when he was forced out of his natural habitat?
        A: This is un-BEAR-able
      TEXT
      canvas_export_file.close
    end

    # This is used to identify the source course of a content export
    def create_context_info(document = nil)
      unless document
        rel_path = File.join(CCHelper::COURSE_SETTINGS_DIR, CCHelper::CONTEXT_INFO)
        path = File.join(@canvas_resource_dir, CCHelper::CONTEXT_INFO)
        file = File.open(path, "w")
        document = Builder::XmlMarkup.new(target: file, indent: 2)
      end

      document.instruct!
      document.context_info("xmlns" => CCHelper::CANVAS_NAMESPACE,
                            "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
                            "xsi:schemaLocation" => "#{CCHelper::CANVAS_NAMESPACE} #{CCHelper::XSD_URI}") do |ci|
        ci.course_id @course.id
        ci.course_name @course.name
        @course.root_account.tap do |a|
          ci.root_account_id a.global_id
          ci.root_account_name a.name
          ci.root_account_uuid a.uuid
          ci.canvas_domain a.domain
        end
      end

      file&.close
      rel_path
    end

    def create_syllabus(io_object = nil)
      syl_rel_path = nil

      unless io_object
        syl_rel_path = File.join(CCHelper::COURSE_SETTINGS_DIR, CCHelper::SYLLABUS)
        path = File.join(@canvas_resource_dir, CCHelper::SYLLABUS)
        io_object = File.open(path, "w")
      end
      io_object << @html_exporter.html_page(@course.syllabus_body || "", "Syllabus")
      io_object.close

      syl_rel_path
    end

    def create_course_settings(migration_id, document = nil)
      if document
        course_file = nil
        rel_path = nil
      else
        course_file = File.new(File.join(@canvas_resource_dir, CCHelper::COURSE_SETTINGS), "w")
        rel_path = File.join(CCHelper::COURSE_SETTINGS_DIR, CCHelper::COURSE_SETTINGS)
        document = Builder::XmlMarkup.new(target: course_file, indent: 2)
      end

      document.instruct!
      document.course("identifier" => migration_id,
                      "xmlns" => CCHelper::CANVAS_NAMESPACE,
                      "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
                      "xsi:schemaLocation" => "#{CCHelper::CANVAS_NAMESPACE} #{CCHelper::XSD_URI}") do |c|
        c.title @course.name
        c.course_code @course.course_code
        c.start_at ims_datetime(@course.start_at, nil)
        c.conclude_at ims_datetime(@course.conclude_at, nil)
        if @course.tab_configuration.present?
          tab_config = []
          @course.tab_configuration.each do |t|
            tab = t.dup
            if tab["id"].is_a?(String)
              # it's an external tool, so translate the id to a migration_id
              tool_id = tab["id"].sub("context_external_tool_", "")
              if (tool = ContextExternalTool.find_for(tool_id, @course, :course_navigation, false))
                tab["id"] = "context_external_tool_#{create_key(tool)}"
              end
            end
            tab_config << tab
          end
          c.tab_configuration tab_config.to_json
        end
        atts = Course.clonable_attributes
        atts -= Canvas::Migration::MigratorHelper::COURSE_NO_COPY_ATTS
        atts << :grading_standard_enabled
        atts << :storage_quota
        atts << :restrict_enrollments_to_course_dates

        if @course.image_url.present?
          atts << :image_url
        elsif @course.image_id.present?
          if (image_att = @course.attachments.active.where(id: @course.image_id).first)
            c.image_identifier_ref(create_key(image_att))
          end
        end

        if @course.banner_image_url.present?
          atts << :banner_image_url
        elsif @course.banner_image_id.present?
          if (image_att = @course.attachments.active.where(id: @course.banner_image_id).first)
            c.banner_image_identifier_ref(create_key(image_att))
          end
        end

        @course.disable_setting_defaults do # so that we don't copy defaulted settings
          atts.uniq.each do |att|
            c.tag!(att, @course.send(att)) unless @course.send(att).nil? || @course.send(att) == ""
          end
          c.tag!(:overridden_course_visibility, @course.overridden_course_visibility)
        end
        if @course.grading_standard
          if @course.grading_standard.context_type == "Account"
            c.grading_standard_id @course.grading_standard.id
          else
            c.grading_standard_identifier_ref create_key(@course.grading_standard)
            add_item_to_export(@course.grading_standard)
          end
        end
        c.root_account_uuid(@course.root_account.uuid) if @course.root_account

        if @course.default_post_policy.present?
          c.default_post_policy { |policy| policy.post_manually(@course.default_post_policy.post_manually?) }
        end

        if @course.time_zone != @course.account.default_time_zone
          c.time_zone @course.time_zone.name
        end

        if @course.account.feature_enabled?(:final_grades_override)
          c.allow_final_grade_override(@course.allow_final_grade_override?)
        end

        if @course.account.feature_enabled?(:course_paces)
          c.enable_course_paces(@course.enable_course_paces)
        end

        if @course.course_sections.active.count > 1
          c.hide_sections_on_course_users_page(@course.hide_sections_on_course_users_page)
        end
      end
      course_file&.close
      rel_path
    end
  end
end
