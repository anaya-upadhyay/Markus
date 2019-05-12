class TagsController < ApplicationController
  include TagsHelper

  before_action :authorize_only_for_admin
  responders :flash

  layout 'assignment_content'

  def index
    @assignment = Assignment.find(params[:assignment_id])

    respond_to do |format|
      format.html
      format.json do
        tags = Tag.includes(:user, :groupings).order(:name)

        tag_info = tags.map do |tag|
          {
            id: tag.id,
            name: tag.name,
            description: tag.description,
            creator: "#{tag.user.first_name} #{tag.user.last_name}",
            use: get_num_groupings_for_tag(tag)
          }
        end

        render json: tag_info
      end
    end
  end

  def edit
    @tag = Tag.find(params[:id])
    @assignment = Assignment.find(params[:assignment_id])
  end

  # Creates a new instance of the tag.
  def create
    new_tag = Tag.new(
      name: params[:create_new][:name],
      description: params[:create_new][:description],
      user: @current_user)

    if new_tag.save
      if params[:grouping_id]
        create_grouping_tag_association(params[:grouping_id], new_tag)
      end
    end

    respond_with new_tag, location: -> { request.headers['Referer'] || root_path }
  end

  def get_all_tags
    Tag.all
  end

  def update
    tag = Tag.find(params[:id])
    tag.name = params[:update_tag][:name]
    tag.description = params[:update_tag][:description]
    tag.save

    respond_with tag, location: -> { request.headers['Referer'] || root_path }
  end

  def destroy
    tag = Tag.find(params[:id])
    tag.destroy
    head :ok
  end

  # Dialog to edit a tag.
  def edit_tag_dialog
    @assignment = Assignment.find(params[:assignment_id])
    @tag = Tag.find(params[:id])

    render partial: 'tags/edit_dialog', handlers: [:erb]
  end

  ###  Upload/Download Methods  ###

  def download
    tags = Tag.includes(:user).order(:name).pluck(:name, :description, 'users.user_name')

    case params[:format]
    when 'csv'
      output = MarkusCSV.generate(tags) do |tag_data|
        tag_data
      end
      format = 'text/csv'
    else
      # Default to yml download.
      output = tags.map do |name, description, user_name|
        {
          name: name,
          description: description,
          user: user_name
        }
      end.to_yaml
      format = 'text/yml'
    end

    send_data output,
              type: format,
              filename: "tag_list.#{params[:format]}",
              disposition: 'attachment'
  end

  def upload
    begin
      data = process_file_upload
    rescue Psych::SyntaxError => e
      flash_message(:error, t('upload_errors.syntax_error', error: e.to_s))
    rescue StandardError => e
      flash_message(:error, e.message)
    else
      if data[:type] == '.csv'
        result = Tag.from_csv(data[:file].read)
        flash_message(:error, result[:invalid_lines]) unless result[:invalid_lines].empty?
        flash_message(:success, result[:valid_lines]) unless result[:valid_lines].empty?
      elsif data[:type] == '.yml'
        result = Tag.from_yml(data[:contents])
        if result.is_a?(StandardError)
          flash_message(:error, result.message)
        end
      end
    end
    redirect_to action: 'index'
  end
end
